create database GAMING_REVIEWS_DB;
use database GAMING_REVIEWS_DB;

create schema gaming_reviews_schema;
use schema gaming_reviews_schema;

CREATE OR REPLACE TABLE metacritic_pc_games(
    game_title VARCHAR(255),
    game_poster VARCHAR(255),
    game_release_date VARCHAR(255),
    game_developer VARCHAR(255),
    genre VARCHAR(255),
    platforms VARCHAR(255),
    product_rating VARCHAR(255),
    overall_metascore FLOAT,
    overall_user_rating FLOAT,
    reviewer_name VARCHAR(255),
    reviewer_type VARCHAR(255),
    rating_given_by_the_reviewer FLOAT,
    review_date VARCHAR(255),
    review VARCHAR(2000)
);

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
TYPE = 'CSV'
SKIP_HEADER = 1
COMPRESSION = 'AUTO'
FIELD_DELIMITER = ','
RECORD_DELIMITER = '\n'
FIELD_OPTIONALLY_ENCLOSED_BY = '\042';

CREATE OR REPLACE STAGE DATA_STAGE
FILE_FORMAT = CSV_FORMAT;

LIST @DATA_STAGE;

COPY INTO GAMING_REVIEWS_DB.GAMING_REVIEWS_SCHEMA.METACRITIC_PC_GAMES
FROM @DATA_STAGE/metacritic_pc_games.csv.gz
ON_ERROR = CONTINUE
FORCE = TRUE;

-- so we have ran this copy command 5 times to have a larger table as well as we will duplicate data into this table.
-- now we will add some random sample data  using sampling to shuffle the data in this table

INSERT INTO metacritic_pc_games
(Select * from metacritic_pc_games TABLESAMPLE BERNOULLI(40) SEED(88)); --select 40% rows at random

INSERT INTO metacritic_pc_games
(Select * from metacritic_pc_games TABLESAMPLE BERNOULLI(40) SEED(88));

INSERT INTO metacritic_pc_games
(Select * from metacritic_pc_games TABLESAMPLE BERNOULLI(40) SEED(88));

-- Now will make a clone of this table to compare the clustered and unclustered table
CREATE OR REPLACE TABLE metacritic_pc_games_clustered CLONE metacritic_pc_games;

Select * FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE 'METACRITIC_PC%';

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT * from METACRITIC_PC_GAMES;

--Since it's hard to know which column in our data will be working best as the clustering key
--this function will help us to know this earlier
SELECT PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('METACRITIC_PC_GAMES','(GAME_TITLE)'));
--"total_constant_partition_count": 0 -> this parameter shows that while running the query how much micro-partition can be pruned or eliminated so this number should be high as possible.

SELECT PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('METACRITIC_PC_GAMES','(GENRE)'));

SELECT PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('METACRITIC_PC_GAMES','(REVIEWER_TYPE)'));

ALTER TABLE METACRITIC_PC_GAMES_CLUSTERED CLUSTER BY (REVIEWER_TYPE);

SHOW TABLES LIKE 'METACRITIC%';

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

--Comparing clustered and unclustered table
Select * from METACRITIC_PC_GAMES
where REVIEWER_TYPE = 'User';


Select * from METACRITIC_PC_GAMES_CLUSTERED
where REVIEWER_TYPE = 'User';


Select * from METACRITIC_PC_GAMES
where REVIEWER_TYPE = 'Critic';

Select * from METACRITIC_PC_GAMES_CLUSTERED
where REVIEWER_TYPE = 'Critic';

Select * from METACRITIC_PC_GAMES
where GAME_DEVELOPER = 'Gearbox Software ';

Select * from METACRITIC_PC_GAMES_CLUSTERED
where GAME_DEVELOPER = 'Gearbox Software ';

Select REVIEWER_TYPE, count(*) from METACRITIC_PC_GAMES
group by REVIEWER_TYPE;

Select REVIEWER_TYPE, count(*) from METACRITIC_PC_GAMES_CLUSTERED
group by REVIEWER_TYPE;


CREATE OR REPLACE TABLE METACRITIC_PC_GAMES_CLUSTERED_CLONE CLONE METACRITIC_PC_GAMES_CLUSTERED;
--the automatic clustering will be OFF for the cloned table.

SHOW TABLES LIKE  'METACRITIC%';

--To start the automatic clustering
ALTER TABLE METACRITIC_PC_GAMES_CLUSTERED_CLONE RESUME RECLUSTER;

SHOW TABLES LIKE  'METACRITIC_PC_GAMES_CLUSTERED_CLONE';

--To suspend the automatic clustering
ALTER TABLE METACRITIC_PC_GAMES_CLUSTERED_CLONE SUSPEND RECLUSTER;

SHOW TABLES LIKE  'METACRITIC_PC_GAMES_CLUSTERED_CLONE';

--To drop the clustering key
ALTER TABLE METACRITIC_PC_GAMES_CLUSTERED_CLONE DROP CLUSTERING KEY;

SHOW TABLES LIKE  'METACRITIC_PC_GAMES_CLUSTERED_CLONE';

--Multiple clustering keys
SELECT SYSTEM$CLUSTERING_INFORMATION('METACRITIC_PC_GAMES','(REVIEWER_TYPE, GAME_POSTER)'); -- the order matters here, we sort it first by reviewer_type, if two rows have same value of reviewer_type then we break the tie based on GAME_POSTER.

SELECT SYSTEM$CLUSTERING_INFORMATION('METACRITIC_PC_GAMES','(REVIEWER_TYPE, GENRE)');

SELECT SYSTEM$CLUSTERING_INFORMATION('METACRITIC_PC_GAMES','(SUBSTRING(GENRE, 0, 5))');
--Note:- so you can use the functions as well in the clustering key. It is powerful when you want the clustering key as year in the data column or month as the clustering key.

