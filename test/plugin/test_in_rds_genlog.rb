require 'helper'

class Rds_GenlogInputTest < Test::Unit::TestCase
  class << self
    def startup
      setup_database
      Timecop.freeze(Time.parse('2015/05/24 18:30 UTC'))
    end

    def shutdown
      cleanup_database
    end

    def setup_database
      client = mysql2_client
      client.query("GRANT ALL ON *.* TO test_rds_user@localhost IDENTIFIED BY 'test_rds_password'")

      client.query <<-EOS
        CREATE PROCEDURE `mysql`.`rds_rotate_general_log`()
        BEGIN
          DECLARE sql_logging BOOLEAN;
          select @@sql_log_bin into sql_logging;
          set @@sql_log_bin=off;
          CREATE TABLE IF NOT EXISTS mysql.general_log2 LIKE mysql.general_log;

          #{insert_general_log_sql}

          DROP TABLE IF EXISTS mysql.general_log_backup;
          RENAME TABLE mysql.general_log TO mysql.general_log_backup, mysql.general_log2 TO mysql.general_log;
          set @@sql_log_bin=sql_logging;
        END
      EOS
    end

    def cleanup_database
      client = mysql2_client
      client.query("DROP USER test_rds_user@localhost")
      client.query("DROP PROCEDURE `mysql`.`rds_rotate_general_log`")
      client.query("DROP TABLE `mysql`.`general_log_custom_backup`")
    end

    def insert_general_log_sql
      if has_thread_id?
        <<-EOS
          INSERT INTO `mysql`.`general_log2` (
            `event_time`, `user_host`, `command_type`, `server_id`, `argument`, `thread_id`)
          VALUES
            ('2015-09-29 15:43:44', 'root@localhost', 'QUERY', 1, 'SELECT 1', 0), 
            ('2015-09-29 15:43:45', 'root@localhost', 'QUERY', 1, 'SELECT 2', 0);
        EOS
      else
        <<-EOS
          INSERT INTO `mysql`.`general_log2` (
            `event_time`, `user_host`, `command_type`, `server_id`, `argument`, `thread_id`)
          VALUES
            ('2015-09-29 15:43:44', 'root@localhost', 'QUERY', 1, 'SELECT 1', 0)
           ,('2015-09-29 15:43:45', 'root@localhost', 'QUERY', 1, 'SELECT 2', 0)
          ;
        EOS
      end
    end

    def has_thread_id?
      client = mysql2_client
      fields = client.query("SHOW FULL FIELDS FROM `mysql`.`general_log`").map {|r| r['Field'] }
      fields.include?('thread_id')
    end

    def mysql2_client
      Mysql2::Client.new(:username => 'root')
    end
  end

  def rotate_general_log
    client = self.class.mysql2_client
    client.query("CALL `mysql`.`rds_rotate_general_log`")
  end

  def setup
    Fluent::Test.setup
    rotate_general_log
  end

  CONFIG = %[
    tag rds-genlog
    host localhost
    username test_rds_user
    password test_rds_password
    interval 0
    backup_table mysql.general_log_custom_backup
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::Rds_GenlogInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal 'rds-genlog', d.instance.tag
    assert_equal 'localhost', d.instance.host
    assert_equal 'test_rds_user', d.instance.username
    assert_equal 'test_rds_password', d.instance.password
    assert_equal 0, d.instance.interval
    assert_equal 'mysql.general_log_custom_backup', d.instance.backup_table
  end

  def test_output
    d = create_driver
    d.run
    records = d.emits

    unless self.class.has_thread_id?
      records.each {|r| r[2]["thread_id"] = "0" }
    end

    assert_equal [
      ["rds-genlog", 1432492200, {"event_time"=>"2015-09-29 15:43:44", "user_host"=>"root@localhost", "command_type"=>"QUERY", "server_id"=>"1", "argument"=>"SELECT 1", "thread_id"=>"0"}],
      ["rds-genlog", 1432492200, {"event_time"=>"2015-09-29 15:43:44", "user_host"=>"root@localhost", "command_type"=>"QUERY", "server_id"=>"1", "argument"=>"SELECT 2", "thread_id"=>"0"}],
  ], records
  end

  def test_backup
    d = create_driver
    d.run

    records = []
    client = self.class.mysql2_client
    general_logs = client.query('SELECT * FROM `mysql`.`general_log_custom_backup`', :cast => false)
    general_logs.each do |row|
      row.each_key {|key| row[key].force_encoding(Encoding::ASCII_8BIT) if row[key].is_a?(String)}
      records.push(row)
    end

    unless self.class.has_thread_id?
      records.each {|r| r["thread_id"] = "0" }
    end

    assert_equal [
      {"event_time"=>"2015-09-29 15:43:44", "user_host"=>"root@localhost", "command_type"=>"QUERY", "server_id"=>"1", "argument"=>"SELECT 1", "thread_id"=>"0"},
      {"event_time"=>"2015-09-29 15:43:45", "user_host"=>"root@localhost", "command_type"=>"QUERY", "server_id"=>"1", "argument"=>"SELECT 2", "thread_id"=>"0"}], records
  end
end
