import dotenv from "dotenv";
import fs from "fs";

// Local dev: load ./config.env if present. In containers/K8s the env vars
// (ATLAS_URI, etc.) are injected by the orchestrator, so this is a no-op.
if (fs.existsSync("./config.env")) {
  dotenv.config({ path: "./config.env" });
}
