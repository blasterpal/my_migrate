# Migrating BAM to Postgresql in many easy steps!

Note: Commands are run in app root unless otherwise noted.

## Requirements

Haskell for using DDL converter ( https://github.com/danchoi/mysql-ddl-parser).

    brew install ghc --64bit --use-llvm
    brew install haskell-platform --64bit --use-llvm
    cd my_migrate
    sh install 


## Creating PostgreSQL DDL

Fetch a backup from Staging or Prod to work against.

### Dump current Mysql DDL

    mysqldump -d -uroot -pfoo9 myapp_development > my_migrate/ddl/mysql.ddl

### Massage your data as neccesary

For example:

  sed "s/DEFAULT '1970-01-01 00:00:0[0,1]'//g" my_migrate/ddl/mysql.ddl > my_migrate/ddl/mysql-cleaned.ddl

### Run Haskell parse program

    cat my_migrate/ddl/mysql-cleaned.ddl | runghc my_migrate/parse.hs > my_migrate/ddl/postgres.ddl

You might see some errors like this, we think it's safe to ignore. 

    my_migrate/parse.hs:38:5:
        Warning: Pattern match(es) are overlapped
                 In an equation for `translate': translate x = ...

### Move INDEX creation to another file

This is so contraints do make inporting CSVs a pain.

    cat my_migrate/ddl/postgres.ddl | grep 'create index' > my_migrate/ddl/postgres-idx.ddl
    cat my_migrate/ddl/postgres.ddl | grep -v 'create index' > my_migrate/ddl/postgres-noidx.ddl

### Dump and load after DDL is good

Create your dumps with reasonable column and field separators. It looks
like PostgreSQL COPY won't allow for multiple characters, so...

You need to ``cd`` because mysqldump creates the files relative to your
location or wants an absolute path.

    cd my_migrate/dumps
    mysqldump -uroot -p myapp_development -T './' --fields-terminated-by='|' --fields-enclosed-by='^'
    sed -i 'bak' 's/\\N/NULL/g' my_migrate/dumps/*.txt

### Clear out your target PostgreSQL DBs

    dropdb myapp_development;createdb myapp_development 

### Load DDL into PostgreSQL

    psql myapp_development <  my_migrate/ddl/postgres-timestamps-noidx.ddl

### Import CSVs into PostgreSQL 

This is how to load a single table into PostgreSQL.

    psql myapp_development -c "copy <table> from '/Users/me/my_migrate/dumps/users.txt' delimiter as '|' NULL 'NULL' csv QUOTE as '^';"

Or use the Ruby program to do them ALL!

   ruby my_migrate/import_csvs.rb

### Load index DDL into PostgreSQL

    psql myapp_development < my_migrate/ddl/postgres-idx.ddl

### Change your database.yml to PostgreSQL 

We don't have to show you that, you're a Rails guru.

### Profit!!!!
