CREATE TABLE IF NOT EXISTS app_user (
    id            VARCHAR(36) PRIMARY KEY,
    username      VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(128) NOT NULL,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS question (
    id          VARCHAR(36) PRIMARY KEY,
    job         VARCHAR(32) NOT NULL,
    dimension   VARCHAR(32) NOT NULL,
    difficulty  INT DEFAULT 3,
    stem        TEXT NOT NULL,
    key_points  TEXT,
    ref_answer  TEXT,
    used_count  INT DEFAULT 0,
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_job (job)
);

CREATE TABLE IF NOT EXISTS interview_session (
    id            VARCHAR(36) PRIMARY KEY,
    user_id       VARCHAR(36),
    job           VARCHAR(32),
    resume_json   TEXT,
    jd_json       TEXT,
    status        VARCHAR(16),
    turn_count    INT DEFAULT 0,
    depth         INT DEFAULT 0,
    last_question TEXT,
    total_score   DOUBLE,
    started_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    finished_at   DATETIME
);

CREATE TABLE IF NOT EXISTS turn (
    id          VARCHAR(36) PRIMARY KEY,
    session_id  VARCHAR(36),
    seq         INT,
    role        VARCHAR(16),
    content     TEXT,
    based_on    VARCHAR(64),
    dimension   VARCHAR(32),
    depth       INT,
    score       INT,
    dimensions_json TEXT COMMENT '各维度得分 JSON',
    tokens_in   INT,
    tokens_out  INT,
    cost        DOUBLE,
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_session (session_id)
);

CREATE TABLE IF NOT EXISTS report (
    id                VARCHAR(36) PRIMARY KEY,
    session_id        VARCHAR(36) UNIQUE,
    total             DOUBLE,
    verdict           VARCHAR(255),
    dimensions_json   TEXT,
    items_json        TEXT,
    next_steps_json   TEXT,
    created_at        DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cost_log (
    id          VARCHAR(36) PRIMARY KEY,
    session_id  VARCHAR(36),
    scene       VARCHAR(32),
    tokens_in   INT,
    tokens_out  INT,
    cost        DOUBLE,
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
);