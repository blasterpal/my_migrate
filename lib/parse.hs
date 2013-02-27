module Main where

import Text.ParserCombinators.Parsec
import Control.Applicative ((<$>), (<*>))
import Text.ParserCombinators.Parsec.Combinator
import Control.Monad (liftM)
import Control.Applicative ((<*))
import Data.List (intercalate)


type Width = String
type Type = String
type ColName = String
data Datatype = Datatype Type (Maybe Width) deriving (Show)
data NullOpt = Null | NotNull deriving (Show)
data DefaultOpt = NoDefault 
                | DefaultNull
                | Default String 
                deriving (Show)

data CreateDefinition = ColumnDefinition ColName Datatype NullOpt DefaultOpt
                      | Index String String String  -- table indexname keycols
                      | PrimaryKey String 
                      | ForeignKeyConstraint String String String String String String
                      | UniqueConstraint String String 
                      deriving (Show)

data Statement = CreateTable String [CreateDefinition] 
               | DropTable String  -- entire string can be copied verbatim
               deriving (Show)

------------------------------------------------------------------------

class Postgres a where
    translate :: a -> String

instance Postgres Statement where 
    translate (CreateTable x ys) = 
        "create table " ++ x ++ " (\n  " ++ format (excludeIndexesAndFKs ys) ++ "\n);\n" 
        where format xs = intercalate ",\n  " (map translate xs) 
              excludeIndexesAndFKs ys = [x | x <- ys, (not . isIndex) x && (not . isFk) x]
    translate (DropTable x) =  "drop table if exists " ++ x ++ " cascade;\n"
    translate x =  "don't know how to translate: "  ++ (show x)

instance Postgres NullOpt where
    translate NotNull = "not null"
    translate Null = ""

instance Postgres DefaultOpt where
    translate (Default x) = "default " ++ x
    translate DefaultNull = ""
    translate NoDefault = ""

instance Postgres CreateDefinition where
    translate (ColumnDefinition c (Datatype "tinyint" (Just "1")) n df) = 
        (intercalate " " $ filter (/= "") parts) 
        where parts = [show c, "boolean", translate n, df']
              df' = case df of
                      Default "'1'" -> "default true"
                      Default "'0'" -> "default false"
                      _ -> ""

    translate (ColumnDefinition c dt n df) = (intercalate " " $ filter (/= "") parts) 
        where parts = [show c, translate dt, translate n, translate df]
    translate (PrimaryKey x) = "primary key (" ++ x ++ ")"
    translate (ForeignKeyConstraint tbl ident col refTbl refTblCol action) = "alter table " ++ tbl ++ " add foreign key (" ++ col ++ ") references "++refTbl++"("++refTblCol++") "++action ++ ";"
    translate (UniqueConstraint ident cols) = "unique (" ++ cols ++ ")" 
    translate x = "-- NO TRANSLATION: " ++ (show x)

instance Postgres Datatype where
    -- generally strip the width
    -- translate (Datatype "tinyint" (Just "'1'")) = "boolean"
    translate (Datatype "tinyint" x) = "smallint"
    translate (Datatype "mediumint" x) = "integer"
    translate (Datatype "int" x) = "integer" 
    translate (Datatype "datetime" x) = "timestamp with time zone" 
    translate (Datatype "longtext" x) = "text" 
    translate (Datatype "mediumtext" x) = "text" 
    translate (Datatype "blob" x) = "bytea" 
    translate (Datatype "longblob" x) = "bytea" 
    translate (Datatype y x) = y 


fkeys statements = filter isFk $ concat [ys | z@(CreateTable x ys) <- statements]

isIndex (Index _ _ _) = True
isIndex _ = False
isFk (ForeignKeyConstraint _ _ _ _  _ _) = True
isFk _ = False

------------------------------------------------------------------------


comment :: GenParser Char st ()
comment = 
    (string "--" >> manyTill anyChar newline >> return ()) <|>
    (string "/*" >> manyTill anyChar (string "*/") >> return ())

notComment = manyTill anyChar (lookAhead (comment <|> eof))

stripComments :: GenParser Char st String
stripComments = do
  optional comment
  xs <- sepBy (spaces >> notComment <* spaces) (comment >> optional spaces >> optional (char ';'))
  optional comment
  return $ intercalate "" xs


------------------------------------------------------------------------
-- Real ddl parsing functions:

dropTable :: GenParser Char st Statement
dropTable = do 
    x <- string "DROP TABLE" <* spaces
    optional (string "IF EXISTS" <* spaces)
    t <- betweenTicks
    xs <- many (noneOf ";")
    return $ DropTable t

createTable :: GenParser Char st Statement
createTable = do 
    x <-  string "CREATE TABLE" <* spaces
    t <- betweenTicks 
    spaces >> char '('  >> spaces 
    ds <- definitions t -- pass down table name
    many (noneOf ";")
    return $ CreateTable t ds  

eol = char '\n'

betweenTicks :: GenParser Char st String
betweenTicks = char '`' >> many (noneOf "`") <* (char '`' >> spaces)

betweenParens :: GenParser Char st String
betweenParens = char '(' >> many (noneOf ")") <* (char ')' >> spaces)

betweenParensTicks :: GenParser Char st String
betweenParensTicks = char '(' >> betweenTicks <* (char ')' >> spaces)

definitions :: String -> GenParser Char st [CreateDefinition]
definitions tablename = many (createDefinition tablename) <* char ')' 
  
createDefinition :: String -> GenParser Char st CreateDefinition
createDefinition tablename = do
    x <- primaryKey <|> index tablename <|> foreignKeyConstraint tablename <|> uniqueConstraint <|> columnDefinition 
    optional (char ',') >> optional eol >> spaces
    return x
     -- <|> check

datatype :: GenParser Char st Datatype 
datatype = do
    t <- many alphaNum
    width <- optionMaybe $ betweenParens
    spaces
    return $ Datatype t width

columnDefinition :: GenParser Char st CreateDefinition
columnDefinition = do 
    tbl <- betweenTicks
    d <- datatype
    optional (string "COLLATE" >> spaces >> (many (noneOf " "))) >> spaces
    n <- optionMaybe (string "NOT NULL") <* spaces
    let nopt = case n of
                  Nothing -> Null
                  _ -> NotNull
    -- serial is a datatype in postgres, like an integer; so it should replace d
    d' <- option d (try $ string "AUTO_INCREMENT" >> return (Datatype "serial" Nothing))
    df <- option NoDefault parseDefault
    return $ ColumnDefinition tbl d' nopt df
  where parseDefault = do
          string "DEFAULT" >> spaces
          (string "NULL" >> return DefaultNull) <|> (do
            x <- many (noneOf "\n,") 
            return $ Default x)

doubleQuote s = "\"" ++ s ++ "\""

keyColumns = char '(' >> liftM (intercalate "," . map doubleQuote) (sepBy betweenTicks (char ',')) <* (char ')' >> spaces)

primaryKey :: GenParser Char st CreateDefinition
primaryKey = string "PRIMARY KEY " >> PrimaryKey `liftM` betweenParensTicks

index :: String -> GenParser Char st CreateDefinition
index tablename = string "KEY " >> Index tablename `liftM` betweenTicks <*> keyColumns 

foreignKeyConstraint :: String -> GenParser Char st CreateDefinition
foreignKeyConstraint tbl = do 
    string "CONSTRAINT " 
    ident <- betweenTicks
    string "FOREIGN KEY "
    col <- keyColumns
    string "REFERENCES "
    reftbl <- betweenTicks
    reftblCol <- betweenParensTicks
    action <- manyTill anyChar (char ',' <|> eol) -- LEAK
    return $ ForeignKeyConstraint tbl ident col reftbl reftblCol action

uniqueConstraint :: GenParser Char st CreateDefinition
uniqueConstraint = string "UNIQUE KEY " >> UniqueConstraint `liftM` betweenTicks <*> keyColumns

statement :: GenParser Char st Statement
statement = dropTable <|> createTable

ddlFile :: GenParser Char st [Statement]
ddlFile = endBy statement (char ';' >> spaces)

test s = do 
  case parse stripComments "" s of 
    Left err -> "Error stripping comments"
    -- Right s' -> s'
    Right s' -> case parse ddlFile "" s' of 
                  Left e -> "No match " ++ show e
                  Right res -> show res

prettyPrint :: [Statement] -> IO ()
prettyPrint xs = 
    mapM_ pprint xs
    where pprint (CreateTable x ys) = do
              putStrLn x
              mapM_ (putStrLn . showCreateDefinition) ys
          pprint _ = return ()

          showCreateDefinition :: CreateDefinition -> String
          showCreateDefinition x = "  " ++ (show x)


indexes statements = filter isIndex $ concat [ys | z@(CreateTable t ys) <- statements]
translateIndex (Index tbl ident cols) = "create index " ++ ident ++ " on " ++ tbl ++ " (" ++ cols ++ ");"

toPostgres :: [Statement] -> IO ()
toPostgres xs = do 
      mapM_ (putStrLn . translate) xs
      mapM_ (putStrLn . translateIndex) $ indexes xs
      mapM_ (putStrLn . translate) $ fkeys xs




main = do 
    s <- getContents
    case parse stripComments "" s of 
      Left err -> putStrLn "Error stripping comments"
      Right s' -> do
          -- writeFile "stripped.sql" s' -- for debugging
          case parse ddlFile "" s' of 
                  Left e -> putStrLn $ "No match " ++ show e
                  Right xs -> do 
                      -- prettyPrint xs
                      toPostgres xs

    

