require 'pry'
require 'yaml'
require 'highline/import'
APP_ROOT = File.dirname(File.expand_path(__FILE__))
require File.expand_path("lib/my_migrate")
include MyMigrate
