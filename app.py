import os, decimal, datetime
import mysql.connector
from flask import Flask, request, session, jsonify

app = Flask(__name__, static_folder="static", static_url_path="")
app.secret_key = "change-me"
DB = dict(host=os.getenv("DB_HOST", "localhost"), user=os.getenv("DB_USER", "root"),password=os.getenv("DB_PASS", ""), database="campus_remarket")
OK = {"ok": True}


def call(proc, *args):
    con = mysql.connector.connect(**DB)
    try:
        cur = con.cursor(dictionary=True)
        cur.callproc(proc, args)
        rows = []
        for result in cur.stored_results():
            rows = result.fetchall()
        for r in rows:
            for k, v in r.items():
                if isinstance(v, decimal.Decimal): r[k] = float(v)
                elif isinstance(v, (datetime.datetime, datetime.date)): r[k] = str(v)
        con.commit()
        return rows
    finally:
        con.close()


def val(v):
    if isinstance(v, bool): return v
    v = "" if v is None else str(v).strip()
    return v or None

def body(*keys):
    d = request.get_json(silent=True) or {}
    return [val(d.get(k)) for k in keys]

def arg(k):
    return val(request.args.get(k))

def me():
    if "uid" not in session: raise PermissionError
    return session["uid"]

def done(status, proc, *args):
    call(proc, *args)
    return jsonify(OK), status

def rows(proc, *args):
    return jsonify(call(proc, *args))


@app.get("/")
def home(): return app.send_static_file("index.html")      # the UI


#Errors raised inside SQL become HTTP errors
@app.errorhandler(PermissionError)
def not_logged_in(e):
    return jsonify(error="Please log in"), 401

@app.errorhandler(mysql.connector.Error)
def db_error(e):
    n = e.errno or 0
    if 30400 <= n <= 30599: return jsonify(error=e.msg), n - 30000
    if str(e.sqlstate).startswith("23"):
        return jsonify(error="Rejected: duplicate value, invalid reference, or record is in use"), 409
    if n == 3819: return jsonify(error="Value breaks a database rule (e.g. negative number)"), 400
    if str(e.sqlstate).startswith("22") or n in (1366, 1265, 1292):
        return jsonify(error="Invalid or missing value"), 400
    print("DB error:", e)
    return jsonify(error="Database error or unavailable. Try again."), 503


# Auth (Python keeps the session; SQL checks the password)
@app.post("/api/register")
def register(): return done(201, "sp_register", *body("name", "email", "password", "role"))

@app.post("/api/login")
def login():
    u = call("sp_login", *body("email", "password"))[0]
    session.update(uid=u["user_id"], name=u["name"], role=u["role"])
    return jsonify(name=u["name"], role=u["role"])

@app.post("/api/logout")
def logout(): session.clear(); return jsonify(OK)

@app.get("/api/me")
def whoami(): return jsonify({"name": session["name"], "role": session["role"]} if "uid" in session else {})

# Categories
@app.get("/api/categories")
def cat_list(): return rows("sp_category_list")
@app.post("/api/admin/categories")
def cat_add(): return done(201, "sp_category_add", me(), *body("name"))
@app.put("/api/admin/categories/<id>")
def cat_upd(id): return done(200, "sp_category_update", me(), id, *body("name"))
@app.delete("/api/admin/categories/<id>")
def cat_del(id): return done(200, "sp_category_delete", me(), id)

# Users
@app.get("/api/admin/users")
def user_list(): return rows("sp_user_list", me())
@app.delete("/api/admin/users/<id>")
def user_del(id): return done(200, "sp_user_delete", me(), id)

# Products
@app.get("/api/products")
def prod_browse(): return rows("sp_product_browse", me(), arg("q"), arg("category"), arg("type"), arg("sort"))
@app.get("/api/my/products")
def prod_mine(): return rows("sp_product_mine", me())
@app.get("/api/admin/products")
def prod_pending(): return rows("sp_product_pending", me())
@app.post("/api/products")
def prod_add(): return done(201, "sp_product_add", me(), *body("categoryId", "title", "description", "listingType", "price", "quantity"))
@app.put("/api/products/<id>")
def prod_upd(id): return done(200, "sp_product_update", me(), id, *body("title", "price", "quantity"))
@app.delete("/api/products/<id>")
def prod_del(id): return done(200, "sp_product_delete", me(), id)
@app.post("/api/admin/products/<id>/<act>")
def prod_moderate(id, act): return done(200, "sp_product_moderate", me(), id, act)

# Orders
@app.post("/api/orders")
def order_place():
    r = call("sp_order_place", me(), *body("productId", "quantity", "method", "rentDays", "offeredItem", "simulateFailure"))[0]
    return jsonify(r), 201
@app.get("/api/orders")
def order_list(): return rows("sp_order_list", me())
@app.post("/api/orders/<id>/complete")
def order_complete(id): return done(200, "sp_order_complete", me(), id)

# Wishlist
@app.get("/api/wishlist")
def wish_list(): return rows("sp_wishlist_list", me())
@app.post("/api/wishlist/<pid>")
def wish_add(pid): return done(200, "sp_wishlist_add", me(), pid)
@app.delete("/api/wishlist/<pid>")
def wish_del(pid): return done(200, "sp_wishlist_remove", me(), pid)

# Reviews/Complaints
@app.post("/api/reviews")
def review_add(): return done(201, "sp_review_add", me(), *body("productId", "rating", "comment"))
@app.post("/api/complaints")
def comp_add(): return done(201, "sp_complaint_add", me(), *body("orderId", "description"))
@app.get("/api/complaints")
def comp_list(): return rows("sp_complaint_list", me())
@app.post("/api/complaints/<id>/resolve")
def comp_resolve(id): return done(200, "sp_complaint_resolve", me(), id, *body("resolution"))

# Reports
@app.get("/api/reports/sales")
def rep_sales(): return rows("sp_report_sales", me())
@app.get("/api/reports/categories")
def rep_cat(): return rows("sp_report_categories", me())


if __name__ == "__main__":
    try: mysql.connector.connect(**DB).close()
    except mysql.connector.Error as e:
        raise SystemExit(f"Cannot connect to MySQL: {e}\nCheck DB_USER / DB_PASS and that db/setup.sql was run.")
    app.run(port=7070)
