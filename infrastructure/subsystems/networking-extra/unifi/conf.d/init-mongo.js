db.getSiblingDB("unifi").createUser({ user: "${MONGO_USER}", pwd: "${MONGO_PASS}", roles: [{ role: "dbOwner", db: "unifi" }] });
db.getSiblingDB("unifi_stat").createUser({ user: "${MONGO_USER}", pwd: "${MONGO_PASS}", roles: [{ role: "dbOwner", db: "unifi_stat" }] });
