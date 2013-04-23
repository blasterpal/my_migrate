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


end
