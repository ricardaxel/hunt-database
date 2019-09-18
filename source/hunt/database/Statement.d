/*
 * Database - Database abstraction layer for D programing language.
 *
 * Copyright (C) 2017  Shanghai Putao Technology Co., Ltd
 *
 * Developer: HuntLabs
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module hunt.database.Statement;

import hunt.database.Database;
import hunt.database.base;
import hunt.database.query.Common;

import hunt.logging;
import hunt.String;
import hunt.Integer;
import hunt.Long;
import hunt.Double;
import hunt.Float;
import hunt.Byte;
import hunt.Short;
import hunt.Nullable;

import std.stdio;
import std.regex;
import std.variant;

/**
 * 
 * See_Also:
 *    https://www.codemeright.com/blog/post/named-parameterized-query-java
 *    https://www.javaworld.com/article/2077706/named-parameters-for-preparedstatement.html
 *    https://github.com/marcosemiao/jdbc-named-parameters/tree/master/src/main/java/fr/ms/sql
 */
class Statement
{
    private Database _db = null;
    private string _sql;
    private bool _isUsed = false;
    private int _lastInsertId;
    private int _affectRows;
    private RowSet _rs;
    private Object[string] _parameters;

    this(Database db)
    {
        _db = db;
    }

    this(Database db, string sql)
    {
        _db = db;
        prepare(sql);
    }

    void prepare(string sql)
    {
        assert(sql.length);
        this._sql = sql;
        _needReset = true;

    }

    private bool _needReset = false;

    void setParameter(R)(string key, R param)
    {
        static if (is(R == int) || is(R == uint))
        {
            _parameters[key] = new Integer(param);
        }
        else static if (is(R == string) || is(R == char) || is(R == byte[]))
        {
            _parameters[key] = new String(param);
        }
        else static if (is(R == bool))
        {
            _parameters[key] = new Boolean(param);
        }
        else static if (is(R == double))
        {
            _parameters[key] = new Double(param);
        }
        else static if (is(R == float))
        {
            _parameters[key] = new Float(param);
        }
        else static if (is(R == short) || is(R == ushort))
        {
            _parameters[key] = new Short(param);
        }
        else static if (is(R == long) || is(R == ulong))
        {
            _parameters[key] = new Long(param);
        }
        else static if (is(R == byte) || is(R == ubyte))
        {
            _parameters[key] = new Byte(param);
        }
        else static if (is(R == class))
        {
            _parameters[key] = param;
        }
        else
        {
            throw new Exception("IllegalArgument not support : " ~ R.stringof);
        }
        _needReset = true;
    }

    // string sql()
    // {
    //     auto conn = _db.getConnection();
    //     scope (exit)
    //         _db.relaseConnection(conn);
    //     return sql(conn);
    // }

    private string sql(SqlConnection conn)
    {
        if (!_needReset)
            return _str;

        string str = _sql;

        foreach (k, v; _parameters)
        {
            auto re = regex(r":" ~ k ~ r"([^\w]*)", "g");
            if ((cast(String) v !is null) || (cast(Nullable!string) v !is null))
            {
                if (_db.getOption().isPgsql() || _db.getOption().isMysql()) {
                    // str = str.replaceAll(re, conn.escapeLiteral(v.toString()) ~ "$1");
                    // str = str.replaceAll(re, v.toString() ~ "$1");
        // warning(str ~ "      " ~ v.toString() ~ "$1");
                // } else if (_db.getOption().isMysql()) {
                    // str = str.replaceAll(re, "'" ~ conn.escape(v.toString()) ~ "'" ~ "$1");
                    str = str.replaceAll(re, "'" ~ v.toString() ~ "'" ~ "$1");
                }
                else
                {
                    str = str.replaceAll(re, quoteSqlString(v.toString()) ~ "$1");
                }
            }
            else
            {
                str = str.replaceAll(re, v.toString() ~ "$1");
            }
        }

        _needReset = false;
        _str = str;
        return str;
    }

    private string _str;

    int execute()
    {
        string execSql = sql(null);

        version (HUNT_SQL_DEBUG)
            logDebug(execSql);

        _rs = _db.query(execSql);

        if (_db.getOption().isMysql()) {
            import hunt.database.driver.mysql.MySQLClient;
            Variant value2 = _rs.property(MySQLClient.LAST_INSERTED_ID);
            if(value2.type != typeid(int)) {
                warning("Not expected type: ", value2.type);
            } else {
                _lastInsertId = value2.get!int();
            }
        } else {
            _lastInsertId = 0;
        }

        _affectRows = _rs.rowCount();
        return _affectRows;
    }

    int lastInsertId()
    {
        return _lastInsertId;
    }

    int affectedRows()
    {
        return _affectRows;
    }


    int count()
    {
        Row res = fetch();
        return res.getInteger(0);
    }

    Row fetch()
    {
        if (!_rs)
            _rs = query();

        foreach(Row r; _rs) {
            return r;
        }

        throw new DatabaseException("RowSet is empty");
    }

    RowSet query()
    {
        string execSql = sql(null);
        _rs = _db.query(execSql);
        return _rs;
    }

    // void close()
    // {
    //     version (HUNT_DEBUG)
    //         info("statement closed");
    // }

    // private void isUsed()
    // {
    //     // scope (exit)
    //     //     _isUsed = true;
    //     if (_isUsed)
    //         throw new DatabaseException("statement was used");
    //     _isUsed = true;
    // }

}