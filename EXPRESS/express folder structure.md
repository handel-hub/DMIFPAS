express-gateway/
│
├── src/
│   ├── app.js                # Express app instance (middleware + routes)
│   ├── server.js             # Server startup + graceful shutdown
│   │
│   ├── config/
│   │   ├── index.js          # Loads env vars, config registry
│   │   ├── database.js       # PostgreSQL (pg or Prisma) connection
│   │   └── redis.js          # (Optional) cache or rate-limiting store
│   │
│   ├── routes/
│   │   ├── index.js          # Central router
│   │   ├── auth.routes.js
│   │   ├── users.routes.js
│   │   ├── jobs.routes.js    # DMIFPAS Gateway → Engine job submissions
│   │   └── files.routes.js   # Uploads, retrieval, metadata
│   │
│   ├── controllers/
│   │   ├── auth.controller.js
│   │   ├── users.controller.js
│   │   ├── jobs.controller.js
│   │   └── files.controller.js
│   │
│   ├── services/
│   │   ├── auth.service.js
│   │   ├── users.service.js
│   │   ├── jobs.service.js
│   │   └── files.service.js
│   │
│   ├── models/
│   │   ├── user.model.js     # If using Sequelize/Prisma → schema files
│   │   ├── job.model.js
│   │   └── file.model.js
│   │
│   ├── middleware/
│   │   ├── errorHandler.js
│   │   ├── asyncWrapper.js
│   │   ├── auth.js
│   │   ├── requestLogger.js
│   │   └── rateLimiter.js
│   │
│   ├── utils/
│   │   ├── logger.js
│   │   ├── validators.js
│   │   └── response.js
│   │
│   └── jobs/
│       └── queuePublisher.js # Gateway → Engine job publisher
│
├── tests/
│   ├── integration/
│   └── unit/
│
├── public/                  # Static files (rare for APIs)
│
├── .env
├── .gitignore
├── package.json
└── README.md
