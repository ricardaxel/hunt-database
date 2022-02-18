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

module hunt.database.base.impl.Connection;

import hunt.database.base.AsyncResult;
import hunt.database.base.impl.command.CommandBase;
import hunt.Functions;

// alias DbConnection = Connection;

alias AsyncDbConnectionHandler = AsyncResultHandler!DbConnection; 
alias DbConnectionAsyncResult = AsyncResult!DbConnection;

alias DbConnectionHandler = Action1!(DbConnection);

/**
 * 
 */
interface DbConnection {

    void initHolder(Holder holder);

    bool isSsl();

    bool isConnected();

    void schedule(ICommand cmd);

    void close(Holder holder);

    void onClosing(DbConnectionHandler handler);

    int getProcessId();

    int getSecretKey();

    interface Holder {

        void handleNotification(int processId, string channel, string payload);

        void handleClosed();

        void handleException(Throwable err);

    }
}
