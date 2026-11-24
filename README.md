# Campus Remarket (Python + MySQL)
Student marketplace (buy/rent/exchange).
Using MySQL and Python

## Where is what?
| File | What it contains |
|---|---|
| `db/schema.sql` | Tables, keys, constraints |
| `db/views_triggers.sql` | Views (joins, reports) and triggers (business rules, auto stock update) |
| `db/procedures.sql` | All CRUD, validation, role checks, the order transaction and reports |
| `db/seed.sql` | Demo users and listings |
| `db/demo_queries.sql` | Plain SELECT / INSERT / UPDATE / DELETE / JOIN / GROUP BY to run by hand |
| `app.py` | URL -> `CALL procedure(...)`, login session, SQL error -> HTTP error |
| `static/index.html` | The UI |

## Run
Needs Python 3.9+ and MySQL 8.0.16+.

1. `pip install -r requirements.txt`
2. Build the database
   `mysql -u root -p < db/setup.sql`
3. Set your MySQL password (default user `root`, empty password):
   Windows CMD: `set DB_PASS=yourpassword`
4. `python app.py`  
5. Open http://localhost:7070

## Demo logins (password `pass123`)
1. admin@campus.edu
password - pass123 
2. seller@campus.edu
password - pass123 
3. buyer@campus.edu
password - pass123

