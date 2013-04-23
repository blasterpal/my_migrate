require 'yaml'
require 'hashie'
require 'mysql2'

require File.join(APP_ROOT,'lib','requirements')
require_relative 'db_checks'
require_relative 'my_migrate/custom_actions'
require_relative 'my_migrate/actions'
module MyMigrate

  def self.config
      begin
        @config ||= Hashie::Mash.new (YAML.load(File.open('./config.yml').read))
      rescue => e
        puts "Error opening config.yml: #{e}"
        exit 1
      end
  end

  def self.actions
    @actions ||= Actions.new 
  end

  def self.help
    puts %( 
      MyMigrate commands:
      'MyMigrate.config' show config object
      'MyMigrate.config.<attribute>' change config value
      'MyMigrate.actions' List actions available
      'MyMigrate.actions.run_all' Run all actions in order
    )
  end

  def self.ruby_mysql_conn
   Mysql2::Client.new(:host => self.config.source.hostname, :username => self.config.source.username, :password => self.config.source.password, :database => self.config.source.database)
  end

  def self.check_for_non_numberic_ids
    r = DbChecks.check_for_non_numeric_ids(MyMigrate.ruby_mysql_conn)
    File.open('./ddl/non_numberic_id_columns.yaml','w') do |f|
      f << pp(r.to_yaml)
    end
    puts "Report written to ./ddl/non_numberic_id_columns.yaml"
  end

  def self.create_non_numeric_to_bigint_ddl
    r = DbChecks.check_for_non_numeric_ids(MyMigrate.ruby_mysql_conn)
    statements = []
    File.open('./ddl/postgres_alter_non_numeric_ids.ddl','w') do |f|
      r.each do |table|
        table[1].each do |column|
          f << "ALTER TABLE #{table[0]} ALTER COLUMN #{column['Field']} TYPE bigint USING CAST (#{column['Field']} as bigint);\n"
        end
      end
    end
    puts "File ./ddl/postgres_alter_non_numeric_ids.ddl created."
  end 

end
