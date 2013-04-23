class DbChecks

  require 'mysql2'
  class << self

    def check_for_non_numeric_ids(client,config={})
      look_for_ids(client,db_tables(client),config)
    end 

    def non_number_id_columns_for_table(client,table_name)
      (client.query "SHOW COLUMNS FROM #{table_name}").select {|col| col['Field'] =~ /.*(_id|_uid)$/ && (col['Type'] =~ /(text|varchar)/) }
    end

    # tables_columnes_to_skip_int_coversion is set in config.yml
    def look_for_ids(client,tables,config = {})
      non_numeric_id_tables = {}
      tables_columns_to_skip_int_coversion = config['columns_to_skip_auto_integer_conversion']
      tables.each do |t| 
        r = non_number_id_columns_for_table(client,t)
        unless r.flatten.empty?
          unless tables_columns_to_skip_int_coversion.nil? || tables_columns_to_skip_int_coversion.empty? ||  tables_columns_to_skip_int_coversion[t].nil?
            r.delete_if {|col| tables_columns_to_skip_int_coversion[t].include? col['Field'] }
          end
          non_numeric_id_tables[t] = r
        end
      end
      non_numeric_id_tables
    end

    def db_tables(client)
      (client.query 'show tables').each(:as => :array).flatten
    end

    def create_non_numberic_yaml(client,config={})
      r = DbChecks.check_for_non_numeric_ids(client,config)
      File.open('./ddl/non_numberic_id_columns.yaml','w') do |f|
        f << pp(r.to_yaml)
      end
      puts "Report written to ./ddl/non_numberic_id_columns.yaml"
    end

    def create_non_numeric_to_bigint_ddl(client,config={})
      r = DbChecks.check_for_non_numeric_ids(client,config)
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
end
