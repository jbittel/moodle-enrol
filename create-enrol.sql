DROP DATABASE IF EXISTS enrol;
CREATE DATABASE enrol;
USE enrol;

DROP TABLE IF EXISTS moodle;
CREATE TABLE moodle (
  id int(10) unsigned NOT NULL auto_increment,
  userid char(9) NOT NULL,
  course_number char(14) NOT NULL,
  role_name char(14) NOT NULL,
  PRIMARY KEY (id)
) TYPE=InnoDB;

CREATE INDEX userid_idx ON moodle (userid);
CREATE INDEX course_number_idx ON moodle (course_number);
