// ecosystem.config.js
// PM2 process manager config
// Usage: pm2 start ecosystem.config.js

module.exports = {
  apps: [
    {
      name        : 'pg-portal',
      script      : 'server/index.js',
      cwd         : '/var/www/pg-portal',
      instances   : 1,
      autorestart : true,
      watch       : false,
      max_memory_restart: '256M',
      env: {
        NODE_ENV : 'production',
        PORT     : 3011,
      },
      // Logs
      out_file    : '/var/log/pg-portal/out.log',
      error_file  : '/var/log/pg-portal/error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
    },
  ],
};
