create database animedb;

use database animedb;

create schema animeschema;

use schema animeschema;

create table users_score(
    user_id int,
    username varchar(255),
    anime_id int,
    anime_title varchar(255),
    rating int
);

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
TYPE = 'CSV'
SKIP_HEADER = 1
COMPRESSION = 'AUTO'
FIELD_DELIMITER = ','
RECORD_DELIMITER = '\n'
FIELD_OPTIONALLY_ENCLOSED_BY = '\042';

--Since the data is greater than 250MB we will use snowsql to put it in a stage and then load it into the table.
CREATE OR REPLACE STAGE DATA_STAGE
FILE_FORMAT = CSV_FORMAT;

COPY INTO users_score
FROM @data_stage/users-score-2023.csv.gz
ON_ERROR = CONTINUE;


Select * from ANIMEDB.ANIMESCHEMA.USERS_SCORE;

INSERT INTO ANIMEDB.ANIMESCHEMA.USERS_SCORE
VALUES
(3112, 'Test', 236, 'Over Drive', 10),
(23434, 'Test', 1323, 'Kuroshitsuji', 3);

--Since the underlying data has been change so query results cache didn't kick in.
Select * from ANIMEDB.ANIMESCHEMA.USERS_SCORE;

--Note:- if you change the warehouse or you change the session still the query results cache will kick in.

--if you change a small thing in the syntax or change in the letters of the query then retrieval optimization will not work.
Select * from ANIMEDB.ANIMESCHEMA.USERS_SCORE where USERNAME = 'LordStew';

Select * from ANIMEDB.ANIMESCHEMA.USERS_SCORE where USERNAME = 'LordStew';

SELECT username, anime_title, rating FROM ANIMEDB.ANIMESCHEMA.USERS_SCORE;

SELECT username, anime_title, rating FROM ANIMEDB.ANIMESCHEMA.USERS_SCORE;

SELECT username, anime_title, rating from ANIMEDB.ANIMESCHEMA.USERS_SCORE; --new query

SELECT username,
anime_title,
rating from ANIMEDB.ANIMESCHEMA.USERS_SCORE;

SELECT username,
anime_title as title,
rating from ANIMEDB.ANIMESCHEMA.USERS_SCORE;

Select * from ANIMEDB.ANIMESCHEMA.USERS_SCORE where RATING >= 9
ORDER BY RATING;

--To set the caching off for the entire session
ALTER SESSION SET USE_CACHED_RESULT = false;

Select * from ANIMEDB.ANIMESCHEMA.USERS_SCORE where RATING >= 9
ORDER BY RATING;
