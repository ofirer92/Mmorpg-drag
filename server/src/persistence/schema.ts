// Drizzle schema. Empty until T-3.1 (users, characters, inventory, progress). Generate migrations with
// `pnpm -C server db:generate`; never hand-edit files in server/drizzle/.
import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

/** Placeholder table so drizzle-kit has a schema to load; replaced in T-3.1. */
export const schemaMeta = pgTable("schema_meta", {
  id: uuid("id").primaryKey().defaultRandom(),
  note: text("note").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
