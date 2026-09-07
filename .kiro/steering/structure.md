---
inclusion: always
---
# Estructura del Proyecto

```
TP3_BD/
├── .kiro/
│   ├── specs/
│   │   └── carga-datos/          # Spec para generación de datos masivos
│   │       ├── requirements.md
│   │       ├── design.md
│   │       └── error-handling.md
│   └── steering/
│       ├── security-standards.md  # Normas de seguridad
│       ├── product.md             # Descripción del proyecto
│       └── structure.md           # Este archivo
├── db/
│   ├── schema.sql                 # Esquema de la base de datos
│   ├── backups/                   # Respaldos de BD
│   └── seeds/                     # Scripts de carga de datos
├── src/                           # Código fuente (si aplica)
├── docs/
│   └── README.md
├── .env.example
├── .gitignore
└── README.md
```

## Convenciones
- **specs/**: Especificaciones técnicas organizadas por feature
- **steering/**: Documentación y normas que guían el desarrollo
- **db/backups/**: Respaldos antes de operaciones masivas
- **db/seeds/**: Scripts de inicialización y carga de datos
