import { isEqual } from "lodash";
import { PostgreSQL } from "./types";
import { query } from "./query";
import { TypedMap } from "../../smc-webapp/app-framework";
import { is_valid_uuid_string } from "../smc-util/misc2";
import { callback2 } from "../smc-util/async-utils";

let licenses: any = undefined;

interface License {
  id: string;
  title?: string;
  expires?: Date;
  activates?: Date;
  upgrades?: object;
  student_upgrades?: object;
  run_limit?: number;
}

async function get_valid_licenses(db): Promise<Map<string, TypedMap<License>>> {
  // Todo -- filter on expiration...
  if (licenses == null) {
    licenses = await callback2(db.synctable.bind(db), {
      table: "site_licenses",
      columns: [
        "title",
        "expires",
        "activates",
        "upgrades",
        "student_upgrades",
        "run_limit"
      ]
      //, where: { expires: { ">=": new Date() }, activates: { "<=": new Date() } }
    });
  }
  return licenses.get();
}

export async function site_license_hook(
  db: PostgreSQL,
  project_id: string,
  dbg: Function
): Promise<void> {
  dbg("site_license_hook -- checking for site license");

  // Check for site licenses, then set the site_license field for this project.

  /*
  The only site license rule right now is that *any* project associated to a course with a
  student whose email address contains ucla.edu gets automatically upgraded.  This is
  a temporary one-off site license that will be redone once we have experience with it.
  */

  const project = await query({
    db,
    select: ["site_license", "course"],
    table: "projects",
    where: { project_id },
    one: true
  });
  dbg(`site_license_hook -- project=${JSON.stringify(project)}`);

  if (project.site_license == null || typeof project.site_license != "object") {
    // no site licenses set for this project.
    return;
  }

  const site_license = project.site_license;
  // Next we check the keys of site_license to see what they contribute,
  // and fill that in.
  const licenses = await get_valid_licenses(db);
  let changed: boolean = false;
  for (const license_id in site_license) {
    if (!is_valid_uuid_string(license_id)) {
      // The site_license is supposed to be a map from uuid's to settings...
      // We could put some sort of error here in case, though I don't know what
      // we would do with it.
      continue;
    }
    const license = licenses.get(license_id);
    let is_valid: boolean;
    if (license == null) {
      dbg(`site_license_hook -- License "${license_id}" does not exist.`);
      is_valid = false;
    } else {
      const expires = license.get("expires");
      const activates = license.get("activates");
      const run_limit = license.get("run_limit");
      if (expires != null && expires <= new Date()) {
        dbg(`site_license_hook -- License "${license_id}" expired ${expires}.`);
        is_valid = false;
      } else if (activates == null || activates > new Date()) {
        dbg(
          `site_license_hook -- License "${license_id}" has not been explicitly activated yet ${activates}.`
        );
        is_valid = false;
      } else if (
        run_limit &&
        run_limit <=
          (await number_of_running_projects_using_license(db, license_id))
      ) {
        dbg(
          `site_license_hook -- License "${license_id}" won't be applied since it would exceed the run limit ${run_limit}.`
        );
        is_valid = false;
      } else {
        is_valid = true;
      }
    }

    if (is_valid) {
      if (license == null) throw Error("bug");
      // The confusing code below is supposed to choose the student_upgrades if the project has a course
      // field and student_upgrades; otherwise, choose the normal upgrades.
      const upgrades =
        project.course != null
          ? license.get("student_upgrades")
          : license.get("upgrades");
      if (upgrades != null) {
        const x = upgrades.toJS();
        dbg(
          `site_license_hook -- Found a valid license "${license_id}".  Upgrade using it to ${JSON.stringify(
            x
          )}.`
        );
        if (!isEqual(site_license[license_id], x)) {
          site_license[license_id] = x;
          changed = true;
        }
      } else {
        dbg(
          `site_license_hook -- Found a valid license "${license_id}", but it offers no upgrades.`
        );
      }
    } else {
      dbg(
        `site_license_hook -- Not currently valid license -- "${license_id}".`
      );
      if (!isEqual(site_license[license_id], {})) {
        // Delete any upgrades, so doesn't provide a benefit.
        site_license[license_id] = {};
        changed = true;
      }
    }
  }

  if (changed) {
    // Now set the site license.
    dbg(
      `site_license_hook -- setup site license=${JSON.stringify(site_license)}`
    );
    await query({
      db,
      query: "UPDATE projects",
      where: { project_id },
      jsonb_set: { site_license }
    });
  }
}

export async function number_of_running_projects_using_license(
  db: PostgreSQL,
  license_id: string
): Promise<number> {
  /* Do a query to count the number of projects that:
      (1) are running,
      (2) have the given license_id has a key in their site_license field with
          a nontrivial value.


  select project_id, site_license, state from projects where state#>>'{state}' in ('running', 'starting') and site_license#>>'{f3942ea1-ff3f-4d9f-937a-c5007babc693}'!='{}';
  */

  const query = `SELECT COUNT(*) FROM projects WHERE state#>>'{state}' IN ('running', 'starting') AND site_license#>>'{${license_id}}'!='{}'`;
  const x = await callback2(db._query.bind(db), { query });
  return parseInt(x.rows[0].count);
}