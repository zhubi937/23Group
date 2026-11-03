import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TaskRecord, SourceRecord, HistoryRecord, uid, cloneTask } from '../domain/Models';
import { changes } from '../domain/Rules';

export class Repository {
  private db: relationalStore.RdbStore | null = null;
  async open(context: common.UIAbilityContext): Promise<void> {
    this.db = await relationalStore.getRdbStore(context, { name: 'screenshot_tasks.db', securityLevel: relationalStore.SecurityLevel.S1 });
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS sources (id TEXT PRIMARY KEY, hash TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, at INTEGER NOT NULL, payload TEXT NOT NULL)');
    await this.db.executeSql('CREATE INDEX IF NOT EXISTS history_task_at ON history(task_id, at)');
    this.db.version = 1;
  }
  private store(): relationalStore.RdbStore { if (!this.db) { throw new Error('数据库尚未打开'); } return this.db; }
  async tasks(includeDeleted: boolean = false): Promise<TaskRecord[]> {
    const rs = await this.store().querySql('SELECT payload FROM tasks');
    const result: TaskRecord[] = [];
    try { while (rs.goToNextRow()) { const v = JSON.parse(rs.getString(0)) as TaskRecord; if (includeDeleted || v.status !== '已删除') { result.push(v); } } }
    finally { rs.close(); }
    return result.sort((a: TaskRecord, b: TaskRecord) => b.updatedAt - a.updatedAt);
  }
  async sources(): Promise<SourceRecord[]> {
    const rs = await this.store().querySql('SELECT payload FROM sources'); const out: SourceRecord[] = [];
    try { while (rs.goToNextRow()) { out.push(JSON.parse(rs.getString(0)) as SourceRecord); } } finally { rs.close(); }
    return out.sort((a: SourceRecord, b: SourceRecord) => b.createdAt - a.createdAt);
  }
  async byHash(hash: string): Promise<SourceRecord | undefined> {
    const rs = await this.store().querySql('SELECT payload FROM sources WHERE hash = ?', [hash]);
    try { return rs.goToFirstRow() ? JSON.parse(rs.getString(0)) as SourceRecord : undefined; } finally { rs.close(); }
  }
  async putSource(s: SourceRecord): Promise<void> {
    await this.store().executeSql('INSERT OR REPLACE INTO sources (id,hash,payload) VALUES (?,?,?)', [s.id, s.hash, JSON.stringify(s)]);
  }
  async removeSource(id: string): Promise<void> {
    const refs = (await this.tasks(true)).filter((t: TaskRecord) => t.sourceIds.includes(id));
    if (refs.length) { throw new Error('此来源仍被事项或历史引用，不能单独删除。可在设置中清空全部本地记录。'); }
    await this.store().executeSql('DELETE FROM sources WHERE id = ?', [id]);
  }
  async history(taskId: string): Promise<HistoryRecord[]> {
    const rs = await this.store().querySql('SELECT payload FROM history WHERE task_id = ? ORDER BY at DESC, rowid DESC', [taskId]);
    const result: HistoryRecord[] = [];
    try { while (rs.goToNextRow()) { result.push(JSON.parse(rs.getString(0)) as HistoryRecord); } } finally { rs.close(); }
    return result;
  }
  async saveTask(task: TaskRecord, action: string, source: SourceRecord | null = null): Promise<TaskRecord> {
    const db = this.store();
    const existing = (await this.tasks(true)).find((t: TaskRecord) => t.id === task.id);
    if (existing && existing.revision !== task.revision) { throw new Error('事项已更新，请返回列表后重新打开'); }
    const next = cloneTask(task); const now = Date.now();
    if (!next.id) { next.id = uid('task'); }
    next.createdAt = existing ? existing.createdAt : now; next.updatedAt = now; next.revision = existing ? existing.revision + 1 : 1;
    if (source && !next.sourceIds.includes(source.id)) { next.sourceIds.push(source.id); }
    const h = new HistoryRecord(); h.id = uid('history'); h.at = now; h.taskId = next.id; h.action = action;
    h.before = existing ? cloneTask(existing) : null; h.after = cloneTask(next); h.sourceId = source ? source.id : ''; h.changes = changes(h.before, next);
    h.sourceSnapshot = source ? JSON.parse(JSON.stringify(source)) as SourceRecord : null;
    if (existing && existing.reminderState !== next.reminderState) { h.changes.push('提醒：' + existing.reminderState + ' → ' + next.reminderState); }
    db.beginTransaction();
    try {
      if (source) { await db.executeSql('INSERT OR REPLACE INTO sources (id,hash,payload) VALUES (?,?,?)', [source.id, source.hash, JSON.stringify(source)]); }
      await db.executeSql('INSERT OR REPLACE INTO tasks (id,payload) VALUES (?,?)', [next.id, JSON.stringify(next)]);
      await db.executeSql('INSERT INTO history (id,task_id,at,payload) VALUES (?,?,?,?)', [h.id, h.taskId, h.at, JSON.stringify(h)]);
      db.commit(); return next;
    } catch (e) { db.rollBack(); throw new Error((e as Error).message || String(e)); }
  }
  async clear(): Promise<void> {
    const db = this.store(); db.beginTransaction();
    try { await db.executeSql('DELETE FROM history'); await db.executeSql('DELETE FROM tasks'); await db.executeSql('DELETE FROM sources'); db.commit(); }
    catch (e) { db.rollBack(); throw new Error((e as Error).message || String(e)); }
  }
}

