import type { Config } from "drizzle-kit";

export default {
  schema: "./src/persistence/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env["DATABASE_URL"] ?? "postgres://hamirpaa:hamirpaa@localhost:5432/hamirpaa",
  },
} satisfies Config;
