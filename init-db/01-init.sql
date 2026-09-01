-- Run automatically on first postgres container init.
-- If the container already has data (volume exists), run this manually via pgcli.

CREATE USER core_user WITH PASSWORD 'your_core_password';
CREATE DATABASE core_db OWNER core_user;

CREATE USER work_user WITH PASSWORD 'your_work_password';
CREATE DATABASE work_db OWNER work_user;

CREATE USER attachments_user WITH PASSWORD 'your_attachments_password';
CREATE DATABASE attachments_db OWNER attachments_user;
