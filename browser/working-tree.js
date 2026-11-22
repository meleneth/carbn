// Domain-neutral authoring worktree operations for isomorphic-git + LightningFS.
// No DOM, framework, Ruby, or application-specific naming assumptions.
import { validateWorkspacePath } from "./workspace-history.js";

export function createWorkingTree({fs, pfs = fs.promises, git, author, root}) {
  if (typeof root !== "string" || !root.startsWith("/")) throw new Error("Git root must be absolute");

  const flush = async () => {
    if (typeof pfs.flush === "function") await pfs.flush();
  };
  const exists = async path => {
    try { await pfs.stat(path); return true; }
    catch (error) { if (error.code === "ENOENT") return false; throw error; }
  };
  const encode = bytes => {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 32768)
      binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
    return btoa(binary);
  };
  const status = () => git.statusMatrix({fs, dir: root});

  return {
    async initialize({branch = "main"} = {}) {
      if (!await exists(root + "/.git"))
        await git.init({fs, dir: root, defaultBranch: branch});
    },
    async hasHead() {
      try {
        await git.resolveRef({fs, dir: root, ref: "HEAD"});
        return true;
      } catch (error) {
        if (error.code === "NotFoundError" || error.code === "ResolveRefError") return false;
        throw error;
      }
    },
    status,
    async ensureInitialCommit({paths, message}) {
      if (await this.hasHead()) return false;
      if (!Array.isArray(paths) || !paths.length) throw new Error("Initial Git paths are required");
      if (typeof message !== "string" || !message.trim()) throw new Error("Initial commit message is required");
      for (const relative of paths) {
        validateWorkspacePath(relative);
        await git.add({fs, dir: root, filepath: relative});
      }
      await git.commit({fs, dir: root, message, author});
      await flush();
      return true;
    },
    async stageAll() {
      const matrix = await status();
      for (const [filepath, , worktree] of matrix) {
        if (worktree === 0) await git.remove({fs, dir: root, filepath});
        else await git.add({fs, dir: root, filepath});
      }
      await flush();
      return matrix.length;
    },
    async commit(message) {
      if (typeof message !== "string" || !message.trim())
        throw new Error("Enter a commit message before committing.");
      const matrix = await status();
      if (!matrix.some(([, head, , stage]) => head !== stage))
        throw new Error("There are no staged changes to commit.");
      const oid = await git.commit({fs, dir: root, message, author});
      await flush();
      return oid;
    },
    async history(depth = 20) {
      if (!await this.hasHead()) return [];
      return git.log({fs, dir: root, depth});
    },
    async readHead(relative) {
      validateWorkspacePath(relative);
      if (!await this.hasHead()) return null;
      try {
        const result = await git.readBlob({fs, dir: root, oid: "HEAD", filepath: relative});
        return result.blob;
      } catch (error) {
        if (error.code === "NotFoundError" || error.code === "ResolveTreeError") return null;
        throw error;
      }
    },
    // Atomically replace a generated snapshot without rewriting the authoring
    // Git history. The caller supplies an ignored scratch directory.
    async replaceFiles({directory, scratch, files}) {
      validateWorkspacePath(directory);
      validateWorkspacePath(scratch);
      if (!files || Array.isArray(files) || typeof files !== "object")
        throw new Error("Snapshot files must be a path-to-bytes map");
      const target = root + "/" + directory;
      const staging = root + "/" + scratch + "/next";
      const previous = root + "/" + scratch + "/previous";
      async function mkdirp(path) {
        if (path === "/" || !path) return;
        if (await exists(path)) return;
        await mkdirp(path.slice(0, path.lastIndexOf("/")) || "/");
        try { await pfs.mkdir(path); }
        catch (error) { if (error.code !== "EEXIST") throw error; }
      }
      async function removeTree(path) {
        if (!await exists(path)) return;
        if ((await pfs.stat(path)).isDirectory()) {
          for (const child of await pfs.readdir(path)) await removeTree(path + "/" + child);
          await pfs.rmdir(path);
        } else await pfs.unlink(path);
      }
      await removeTree(staging);
      await removeTree(previous);
      await mkdirp(staging);
      try {
        for (const [relative, bytes] of Object.entries(files).sort(([a], [b]) => a.localeCompare(b))) {
          validateWorkspacePath(relative);
          if (!(bytes instanceof Uint8Array)) throw new Error(`File ${relative} must contain bytes`);
          const file = staging + "/" + relative;
          await mkdirp(file.slice(0, file.lastIndexOf("/")));
          await pfs.writeFile(file, bytes);
        }
        const hadPrevious = await exists(target);
        if (hadPrevious) await pfs.rename(target, previous);
        try {
          await pfs.rename(staging, target);
        } catch (error) {
          if (hadPrevious) await pfs.rename(previous, target);
          throw error;
        }
        await removeTree(previous);
        await flush();
      } catch (error) {
        await removeTree(staging);
        throw error;
      }
    },
    async export({requiredPaths = []} = {}) {
      if (!await this.hasHead()) throw new Error("Workspace has no Git history.");
      const entries = {};
      async function collect(directory, prefix = "") {
        for (const name of (await pfs.readdir(directory)).sort()) {
          const absolute = directory + "/" + name;
          const relative = prefix ? prefix + "/" + name : name;
          if ((await pfs.stat(absolute)).isDirectory()) await collect(absolute, relative);
          else entries[relative] = encode(new Uint8Array(await pfs.readFile(absolute)));
        }
      }
      await flush();
      await collect(root);
      if (!entries[".git/HEAD"]) throw new Error("Git HEAD is missing from workspace archive.");
      for (const path of requiredPaths) {
        validateWorkspacePath(path);
        if (!entries[path]) throw new Error(`Required workspace file missing: ${path}`);
      }
      return entries;
    }
  };
}
