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
module hunt.database.postgresql.impl.codec.PgParamDesc;

import hunt.database.postgresql.impl.codec.DataType;
import hunt.database.postgresql.impl.codec.DataTypeCodec;
import hunt.database.postgresql.impl.codec.DataTypeDesc;

import hunt.database.base.impl.ParamDesc;
import hunt.database.postgresql.impl.util.Util;

import hunt.collection.List;
import hunt.Exceptions;
import hunt.logging.ConsoleLogger;

import std.array;
import std.algorithm;
import std.conv;
import std.variant;


/**
 * @author <a href="mailto:emad.albloushi@gmail.com">Emad Alblueshi</a>
 */
class PgParamDesc : ParamDesc {

    // OIDs
    private DataTypeDesc[] _paramDataTypes;

    this(DataTypeDesc[] paramDataTypes) {
        this._paramDataTypes = paramDataTypes;
    }

    DataTypeDesc[] paramDataTypes() {
        return _paramDataTypes;
    }

    override
    string prepare(List!(Variant) values) {
        if (values.size() != cast(int)_paramDataTypes.length) {
            return buildReport(values);
        }
        for (int i = 0;i < cast(int)_paramDataTypes.length;i++) {
            DataTypeDesc paramDataType = _paramDataTypes[i];
            Variant value = values.get(i);
            Variant val = DataTypeCodec.prepare(cast(DataType)paramDataType.id, value);
            version(HUNT_DB_DEBUG) tracef("DataType: %s, value: %s, val: %s", paramDataType, value, val);
            if (val != value) {
                if (val == DataTypeCodec.REFUSED_SENTINEL) {
                    return buildReport(values);
                } else {
                    values.set(i, val);
                }
            }
        }
        return null;
    }

    private string buildReport(List!(Variant) values) {
        return Util.buildInvalidArgsError(values.toArray(), 
            paramDataTypes.map!(type => cast(TypeInfo)type.decodingType).array());
    }

    override
    string toString() {
        return "PgParamDesc{paramDataTypes=" ~ _paramDataTypes.to!string() ~ "}";
    }
}
