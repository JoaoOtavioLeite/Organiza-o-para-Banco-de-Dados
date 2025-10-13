# Banco de Dados - Modelo inicial para "Airbnb"

Arquivos gerados:
- `schema.sql` — DDL completo para PostgreSQL (tabelas, índices, constraints, triggers)
- `sample_queries.sql` — Exemplos de inserts, testes e consultas úteis

Requisitos
- PostgreSQL 12+ (recomendo 13 ou 14)
- Extensão `btree_gist` (o script cria automaticamente com CREATE EXTENSION)

Como rodar (Windows / PowerShell)
1. Crie um banco no Postgres e conecte-se com um usuário que tenha permissões para criar extensões e tabelas.
2. Rode:

```powershell
psql -d seu_banco -f "c:\Users\Pichau\OneDrive\Desktop\banco de dados tarefa\schema.sql"
psql -d seu_banco -f "c:\Users\Pichau\OneDrive\Desktop\banco de dados tarefa\sample_queries.sql"
```

Observações rápidas
- A constraint `bookings_no_overlap` usa `btree_gist` e `daterange(...)` para evitar double-booking por `listing_id`.
- A trigger `fn_check_review_allowed` impede inserir reviews para reservas que não estejam com `status = 'completed'` e cujo `end_date` já tenha passado.
- A trigger `fn_update_listing_rating` recalcula `avg_rating` e `ratings_count` sempre que reviews mudam.
- Para funcionalidades geoespaciais, substitua latitude/longitude por tipos do PostGIS.


