const databaseName = process.env.DATABASE_NAME || "oneinstack";
const databaseUser = process.env.DATABASE_USER || "oneinstack";
const databasePassword = process.env.DATABASE_PASSWORD ||
  require("fs").readFileSync(process.env.DATABASE_PASSWORD_FILE, "utf8").trim();

if (!databasePassword) {
  throw new Error("DATABASE_PASSWORD is required");
}

db.getSiblingDB(databaseName).createUser({
  user: databaseUser,
  pwd: databasePassword,
  roles: [{ role: "readWrite", db: databaseName }],
});
