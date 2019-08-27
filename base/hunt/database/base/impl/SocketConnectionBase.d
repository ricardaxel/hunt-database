/*
 * Copyright (C) 2019, HuntLabs
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

module hunt.database.base.impl.SocketConnectionBase;

import hunt.database.base.impl.command;
import hunt.database.base.impl.Connection;
import hunt.database.base.impl.Notice;
import hunt.database.base.impl.Notification;
import hunt.database.base.impl.PreparedStatement;
import hunt.database.base.impl.PreparedStatementCache;
import hunt.database.base.impl.StringLongSequence;

import hunt.collection.ArrayDeque;
import hunt.collection.Deque;
import hunt.Exceptions;
import hunt.logging.ConsoleLogger;
import hunt.net.AbstractConnection;
import hunt.net.Connection;
import hunt.net.Exceptions;
import hunt.Object;

import std.container.dlist;
import std.conv;

/**
 * @author <a href="mailto:julien@julienviet.com">Julien Viet</a>
 */
abstract class SocketConnectionBase : DbConnection {

    // private static final Logger logger = LoggerFactory.getLogger(SocketConnectionBase.class);

    enum Status {
        CLOSED, CONNECTED, CLOSING
    }

    protected PreparedStatementCache psCache;
    private int preparedStatementCacheSqlLimit;
    private StringLongSequence psSeq; // = new StringLongSequence();
    // private ArrayDeque<CommandBase<?>> pending = new ArrayDeque<>();
    private DList!(ICommand) pending;
    
    // private Context context;
    private int inflight;
    private Holder holder;
    private int pipeliningLimit;

    protected AbstractConnection _socket;
    protected Status status = Status.CONNECTED;

    this(AbstractConnection socket,
                        bool cachePreparedStatements,
                        int preparedStatementCacheSize,
                        int preparedStatementCacheSqlLimit,
                        int pipeliningLimit) {
        this._socket = socket;
        this.psSeq = new StringLongSequence();
        // this.context = context;
        this.pipeliningLimit = pipeliningLimit;
        this.psCache = cachePreparedStatements ? new PreparedStatementCache(preparedStatementCacheSize, this) : null;
        this.preparedStatementCacheSqlLimit = preparedStatementCacheSqlLimit;
    }

    // Context context() {
    //     return context;
    // }

    void initialization() {

        ConnectionEventHandlerAdapter adapter = new ConnectionEventHandlerAdapter();
        adapter.onClosed(&handleClosed);
        adapter.onException(&handleException);
        adapter.onMessageReceived((Connection conn, Object msg) {
            version(HUNT_DB_DEBUG) tracef("A message received. %s", typeid(msg));
            try {
                handleMessage(conn, msg);
            } catch (Throwable e) {
                handleException(conn, e);
            }
        });

        _socket.setHandler(adapter);
    }

    AbstractConnection socket() {
        return _socket;
    }

    bool isSsl() {
        return _socket.isSecured();
    }

    override
    void initHolder(Holder holder) {
        this.holder = holder;
    }

    override
    int getProcessId() {
        throw new UnsupportedOperationException();
    }

    override
    int getSecretKey() {
        throw new UnsupportedOperationException();
    }

    override
    void close(Holder holder) {
        if (status == Status.CONNECTED) {
            status = Status.CLOSING;
            _socket.close();
        }
        // if (Vertx.currentContext() == context) {
        //     if (status == Status.CONNECTED) {
        //         status = Status.CLOSING;
        //         // Append directly since schedule checks the status and won't enqueue the command
        //         pending.add(CloseConnectionCommand.INSTANCE);
        //         checkPending();
        //     }
        // } else {
        //     context.runOnContext(v -> close(holder));
        // }
    }

    void schedule(ICommand cmd) {
        if (!cmd.handlerExist()) {
            throw new IllegalArgumentException();
        }
        // if (Vertx.currentContext() != context) {
        //     throw new IllegalStateException();
        // }

        // Special handling for cache
        PreparedStatementCache psCache = this.psCache;
        PrepareStatementCommand psCmd = cast(PrepareStatementCommand) cmd;
        if (psCache !is null && psCmd !is null) {
            if (psCmd.sql().length > preparedStatementCacheSqlLimit) {
                // do not cache the statements
                return;
            }
            CachedPreparedStatement cached = psCache.get(psCmd.sql());
            if (cached !is null) {
                psCmd.cached = cached;
                ResponseHandler!(PreparedStatement) handler = psCmd.handler;
                cached.get(handler);
                return;
            } else {
                if (psCache.size() >= psCache.getCapacity() && !psCache.isReady()) {
                    // only if the prepared statement is ready then it can be evicted
                } else {
                    psCmd._statement = psSeq.next();
                    psCmd.cached = cached = new CachedPreparedStatement();
                    psCache.put(psCmd.sql(), cached);
                    ResponseHandler!(PreparedStatement) a = psCmd.handler;
                    (cast(CachedPreparedStatement) psCmd.cached).get(a);
                    implementationMissing(false);
// FIXME: Needing refactor or cleanup -@zxp at 8/14/2019, 10:54:17 AM                    
// to check
                    // psCmd.handler = cast(ResponseHandler!(PreparedStatement)) psCmd.cached;
                }
            }
        }

        //
        if (status == Status.CONNECTED) {
            pending.insertBack(cmd);
            checkPending();
        } else {
            cmd.fail(new IOException("Connection not open " ~ status.to!string()));
        }
    }


    private void checkPending() {
        // ConnectionEventHandler ctx = _socket.getHandler();
        if (inflight < pipeliningLimit) {
            ICommand cmd;
            while (inflight < pipeliningLimit && (cmd = pollPending()) !is null) {
                inflight++;
                // _socket.write(cast(Object)cmd)
                version(HUNT_DB_DEBUG_MORE) {
                    tracef("chekcing %s ... ", typeid(cast(Object)cmd));
                } else version(HUNT_DB_DEBUG) {
                    tracef("chekcing %s ... ", typeid(cast(Object)cmd));
                } 
                _socket.encode(cast(Object)cmd);
            }
            // ctx.flush();
        }
    }

    private ICommand pollPending() {
        if(pending.empty())
            return null;
        ICommand c = pending.front;
        pending.removeFront();
        return c;

    }

    private void handleMessage(Connection conn, Object msg) {
        version(HUNT_DB_DEBUG) tracef("handling a message: %s", typeid(msg));

        ICommandResponse resp = cast(ICommandResponse) msg;
        if (resp !is null) {
            // tracef("inflight=%d", inflight);
            inflight--;
            checkPending();
            resp.notifyCommandResponse();
            return;
        } 

        Notification n = cast(Notification) msg;
        if (n !is null) {
            handleNotification(n);
            return;
        }

        Notice notice = cast(Notice) msg;
        if (notice !is null) {
            handleNotice(notice);
        }
    }

    private void handleNotification(Notification response) {
        if (holder !is null) {
            holder.handleNotification(response.getProcessId(), response.getChannel(), response.getPayload());
        }
    }

    private void handleNotice(Notice notice) {
        notice.log();
    }

    private void handleClosed(hunt.net.Connection.Connection v) {
        handleClose(null);
    }

    private void handleException(hunt.net.Connection.Connection c, Throwable t) {
        DecoderException err = cast(DecoderException) t;
        if (err !is null) {
            t = err.next;
        }
        handleClose(t);
    }

    private void handleClose(Throwable t) {
        if (status != Status.CLOSED) {
            status = Status.CLOSED;
            // if (t !is null) {
            //     synchronized (this) {
            //         if (holder !is null) {
            //             holder.handleException(t);
            //         }
            //     }
            // }
            // Throwable cause = t is null ? new VertxException("closed") : t;
            // CommandBase<?> cmd;
            // while ((cmd = pending.poll()) !is null) {
            //     CommandBase<?> c = cmd;
            //     context.runOnContext(v -> c.fail(cause));
            // }
            // if (holder !is null) {
            //     holder.handleClosed();
            // }
        }
    }
}

