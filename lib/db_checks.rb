class DbChecks

  require 'mysql2'
  class << self
    def check_for_non_numeric_ids(client)
      look_for_ids client,db_tables(client)
    end 
    
    def non_number_id_columns(client,table_name)
      (client.query "SHOW COLUMNS FROM #{table_name}").select {|col| col['Field'] =~ /.*(_id|_uid)$/ && (col['Type'] =~ /(text|varchar)/) }
    end

    def look_for_ids(client,tables)
      non_numeric_id_tables = {}
      tables.each do |t| 
        r = non_number_id_columns(client,t)
        unless r.flatten.empty?
          non_numeric_id_tables[t] = r
        end
      end
      non_numeric_id_tables
    end

    def db_tables(client)
      (client.query 'show tables').each(:as => :array).flatten
    end
  end
end
