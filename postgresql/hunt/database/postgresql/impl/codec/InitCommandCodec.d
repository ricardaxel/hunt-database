/*
 * Copyright (C) 2018 Julien Viet
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
module hunt.database.postgresql.impl.codec.InitCommandCodec;

import hunt.database.postgresql.impl.codec.ErrorResponse;
import hunt.database.postgresql.impl.codec.PasswordMessage;
import hunt.database.postgresql.impl.codec.PgCommandCodec;
import hunt.database.postgresql.impl.codec.PgEncoder;
import hunt.database.postgresql.impl.codec.StartupMessage;

import hunt.database.base.impl.TxStatus;
import hunt.database.base.impl.command.CommandResponse;
import hunt.database.base.impl.Connection;
import hunt.database.base.impl.command.InitCommand;
import hunt.database.postgresql.impl.PostgreSQLSocketConnection;

import hunt.logging.ConsoleLogger;
import hunt.Exceptions;

class InitCommandCodec : PgCommandCodec!(DbConnection, InitCommand) {

    private PgEncoder encoder;
    private string encoding;

    this(InitCommand cmd) {
        super(cmd);
    }

    override
    void encode(PgEncoder encoder) {
        version(HUNT_DB_DEBUG) tracef("running here");
        this.encoder = encoder;
        encoder.writeStartupMessage(new StartupMessage(cmd.username(), cmd.database(), cmd.properties()));
        // encoder.flush();
    }

    override
    void handleAuthenticationMD5Password(byte[] salt) {
        version(HUNT_DB_DEBUG_MORE) tracef("salt: %(%02X %)", salt);
        encoder.writePasswordMessage(new PasswordMessage(cmd.username(), cmd.password(), salt));
        encoder.flush();
    }

    override
    void handleAuthenticationClearTextPassword() {
        version(HUNT_DB_DEBUG) tracef("running here");
        encoder.writePasswordMessage(new PasswordMessage(cmd.username(), cmd.password(), null));
        encoder.flush();
    }

    override
    void handleAuthenticationOk() {
        version(HUNT_DB_DEBUG) info("Authentication done.");
//      handler.handle(Future.succeededFuture(conn));
//      handler = null;
    }

    override
    void handleParameterStatus(string key, string value) {
        version(HUNT_DB_DEBUG_MORE) tracef("key: %s, value: %s", key, value);
        if(key == "client_encoding") {
            encoding = value;
        }
    }

    override
    void handleBackendKeyData(int processId, int secretKey) {
        version(HUNT_DB_DEBUG) tracef("processId: %d, secretKey: %d", processId, secretKey);
        (cast(PgSocketConnection)cmd.connection()).processId = processId;
        (cast(PgSocketConnection)cmd.connection()).secretKey = secretKey;
    }

    override
    void handleErrorResponse(ErrorResponse errorResponse) {
        version(HUNT_DB_DEBUG) warningf("errorResponse: %s", errorResponse.toString());
        CommandResponse!(DbConnection) resp = failure!DbConnection(errorResponse.toException());
        if(completionHandler !is null) {
            resp.cmd = cmd;
            completionHandler(resp);
        }
    }

    override
    void handleReadyForQuery(TxStatus txStatus) {
        version(HUNT_DB_DEBUG) tracef("txStatus: %s, encoding: %s", txStatus, encoding);
        // The final phase before returning the connection
        // We should make sure we are supporting only UTF8
        // https://www.postgresql.org/docs/9.5/static/multibyte.html#MULTIBYTE-CHARSET-SUPPORTED
        // Charset cs = null;
        // try {
        //     cs = Charset.forName(encoding);
        // } catch (Exception ignore) {
        // }
        CommandResponse!(DbConnection) resp;
        if(encoding != "UTF8") {
            resp = failure!(DbConnection)(encoding ~ " is not supported in the client only UTF8");
        } else {
            resp = success!(DbConnection)(cmd.connection());
        }
        if(completionHandler !is null) {
            resp.cmd = cmd;
            completionHandler(resp);
        }
    }
}