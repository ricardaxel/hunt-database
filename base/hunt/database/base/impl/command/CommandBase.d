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

module hunt.database.base.impl.command.CommandBase;

import hunt.database.base.impl.command.CommandResponse;


interface ICommand {
    void fail(Throwable err);

    bool handlerExist();
}

/**
 * @author <a href="mailto:julien@julienviet.com">Julien Viet</a>
 */
abstract class CommandBase(R) : ICommand {

    ResponseHandler!R handler;


    final bool handlerExist() { return handler !is null; }

    final void fail(Throwable err) {
        handler(failure!R(err));
    }

    void notifyResponse(CommandResponse!(R) response) {
        if(handler !is null) {
            handler(response);
        }
    }
}
