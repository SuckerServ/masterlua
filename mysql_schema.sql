CREATE TABLE IF NOT EXISTS `users` (
  `id` mediumint(9) NOT NULL AUTO_INCREMENT,
  `domain` varchar(32) NOT NULL,
  `name` varchar(32) NOT NULL,
  `pubkey` varchar(51) NOT NULL DEFAULT 0,
  `rights` varchar(8) NOT NULL DEFAULT 'user',
  PRIMARY KEY (`id`),
  KEY `domain` (`domain`),
  UNIQUE (`name`, `domain`)
) ENGINE=MyISAM  DEFAULT CHARSET=ascii ;