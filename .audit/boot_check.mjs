// Simulate Pi's discovery: import every *.ts in the extensions dir and confirm each one loads and
// exports a default function. A test file parked in that folder runs its top-level code on every
// `pi` launch, which is how a suite of passing tests killed the app at startup.
import { readdirSync } from "node:fs";

const dir = "C:/Users/tnguy/.pi/agent/extensions";
const files = readdirSync(dir).filter((f) => f.endsWith(".ts"));
console.log("discovered extension files:", files.join(", "));

let bad = 0;
for (const f of files) {
	const url = "file:///C:/Users/tnguy/.pi/agent/extensions/" + f;
	try {
		const mod = await import(url);
		const ok = typeof mod.default === "function";
		if (!ok) bad += 1;
		console.log(`  ${f}: ${ok ? "default export function (extension)" : "NO default function — Pi would reject it"}`);
	} catch (error) {
		bad += 1;
		console.log(`  ${f}: THROWS ON LOAD — ${String(error).split("\n")[0]}`);
	}
}
console.log(bad === 0 ? "\nall extension files load cleanly" : `\n${bad} file(s) would break boot`);
process.exit(bad === 0 ? 0 : 1);
