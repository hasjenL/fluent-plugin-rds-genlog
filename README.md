# This plugin was made based off the slowlog plugin code.  This new plugin fluent-plugin-rds-genlog [![Build Status](https://travis-ci.org/jenlagrutta/fluent-plugin-rds-genlog.png)](https://travis-ci.org/jenlagrutta/fluent-plugin-rds-genlog/)


## RDS Setting

[Working with MySQL Database Log Files / aws documentation](http://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.Concepts.MySQL.html)

- Set the `general_log` parameter to `1`

## Overview
***AWS RDS general_log*** input plugin.

1. **"CALL mysql.rds_rotate_general_log"**
2. **"SELECT * FROM general_log_backup"**
3. **"INSERT INTO yourdb.general_log_custom_backup SELECT * FROM general_log_backup"** (if you want to take a backup)

every 10 seconds from AWS RDS.

## Configuration

```config
<source>
  type rds_genlog
  tag rds-genlog
  host [RDS Hostname]
  username [RDS Username]
  password [RDS Password]
  backup_table [Your Backup Tablename]
</source>
```

### Example GET RDS general_log

```config
<source>
  type rds_genlog
  tag rds-genlog
  host [RDS Hostname]
  username [RDS Username]
  password [RDS Password]
  interval 10
  backup_table [Your Backup Tablename]
</source>

<match rds-genlog>
  type copy
 <store>
  type file
  path /var/log/general_log
 </store>
</match>
```

#### output data format

```
2013-03-08T16:04:43+09:00       rds-genlog     {"start_time":"2013-03-08 07:04:38","user_host":"rds_db[rds_db] @  [192.0.2.10]","event_time":"00:00:00","command_type":"QUERY", "server_id":"100000000","argument":"select foo from bar"}
2013-03-08T16:04:43+09:00       rds-genlog     {"start_time":"2013-03-08 07:04:38","user_host":"rds_db[rds_db] @  [192.0.2.10]","event_time":"00:00:00","command_type":"QUERY", "server_id":"100000000","argument":"select sleep(2)"}
```

#### if not connect

- td-agent.log

```
2013-06-29 00:32:55 +0900 [error]: fluent-plugin-rds-genlog: cannot connect RDS
```

