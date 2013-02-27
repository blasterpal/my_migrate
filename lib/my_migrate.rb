require 'yaml'
require 'hashie'
require File.join(APP_ROOT,'lib','requirements')
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
end
