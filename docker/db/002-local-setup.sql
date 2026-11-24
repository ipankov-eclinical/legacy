-- Local dev only: admin / password.
UPDATE tblUser SET
  Password = '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
  FailedAttempts = 0, Locked = 0, Display = 1
WHERE UserName = 'admin';

-- No eISF in this stack: serve eDocs from SOMS itself.
INSERT INTO tblConfigurationOption (OptionID, OptionDescription, OptionValue)
VALUES ('documents.eisf_enabled', 'Enable eISF document shell', '0')
ON DUPLICATE KEY UPDATE OptionValue = VALUES(OptionValue);

-- Keep idle sessions alive for 24h (default 1200s). Read once per session into
-- $_SESSION['IDLE_TIMEOUT'], so it applies to sessions started after the change.
UPDATE tblConfiguration SET IdleTimeout = 86400 WHERE ConfigID = 1;
