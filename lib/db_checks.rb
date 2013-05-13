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
    
    def create_non_numeric_to_bigint_ddl_mysql(client,config={})
      r = DbChecks.check_for_non_numeric_ids(client,config)
      statements = []
      File.open('./ddl/mysql_alter_non_numeric_ids.ddl','w') do |f|
        r.each do |table|
          table[1].each do |column|
            f << "ALTER TABLE #{table[0]} MODIFY #{column['Field']} BIGINT UNSIGNED;\n"
          end
        end
      end
      puts "File ./ddl/mysql_alter_non_numeric_ids.ddl created."
    end 


    def _bigint_conversion_truncation_commands(client,config={})
      r = DbChecks.check_for_non_numeric_ids(client,config)
      statements = []
      script = './ddl/biginit_conversion_truncate_check.sql'
      File.open(script,'w') do |f|
        r.each do |table|
          tbl_name = table.first
          columns = table[1].collect{|ea| ea['Field']}
          columns_in_sel = columns.join('--')
          sel_col = columns.collect {|ea| "CAST(#{ea} as UNSIGNED)"}
          where_col = columns.collect {|ea| "CAST(#{ea} as UNSIGNED) = 0"}
          table_sel = %(SELECT "TABLE:#{tbl_name}", "COLS:#{columns_in_sel}",  id, #{sel_col.join(',')} FROM #{tbl_name} WHERE #{where_col.join(' OR ')};\n)
          # SELECT id,col1,col2, cast(col1 as unsigned), cast(col1 as unsigned) where cast(col1 as unsigned) < 1 AND cast(col1 as unsigned) < 1
          f << table_sel
        end
      end
      puts "File #{script}  created."
    end 

  end
end
