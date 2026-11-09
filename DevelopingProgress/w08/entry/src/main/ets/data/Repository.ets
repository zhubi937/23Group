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
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS source_history (source_id TEXT NOT NULL, history_id TEXT NOT NULL, task_id TEXT NOT NULL, PRIMARY KEY(source_id, history_id))');
    if ((this.db.version || 1) < 2) {
      const rs = await this.db.querySql('SELECT payload FROM history'); const old: HistoryRecord[] = [];
      try { while (rs.goToNextRow()) { old.push(JSON.parse(rs.getString(0)) as HistoryRecord); } } finally { rs.close(); }
      this.db.beginTransaction();
      try { for (const h of old) { await this.indexHistory(h); } this.db.commit(); this.db.version = 2; }
      catch (e) { this.db.rollBack(); throw new Error('来源历史迁移未完成，原数据已保留：' + (e as Error).message); }
    }
  }
  private store(): relationalStore.RdbStore { if (!this.db) { throw new Error('数据库尚未打开'); } return this.db; }
  async tasks(includeDeleted: boolean = false): Promise<TaskRecord[]> {
    const rs = await this.store().querySql('SELECT payload FROM tasks');
    const result: TaskRecord[] = [];
    try { while (rs.goToNextRow()) { const v = JSON.parse(rs.getString(0)) as TaskRecord; v.context = v.context || ''; if (includeDeleted || v.status !== '已删除') { result.push(v); } } }
    finally { rs.close(); }
    return result.sort((a: TaskRecord, b: TaskRecord) => b.updatedAt - a.updatedAt);
  }
  async sources(): Promise<SourceRecord[]> {
    const rs = await this.store().querySql('SELECT payload FROM sources'); const out: SourceRecord[] = [];
    try { while (rs.goToNextRow()) { out.push(this.normalizeSource(JSON.parse(rs.getString(0)) as SourceRecord)); } } finally { rs.close(); }
    return out.sort((a: SourceRecord, b: SourceRecord) => b.createdAt - a.createdAt);
  }
  async byHash(hash: string): Promise<SourceRecord | undefined> {
    const rs = await this.store().querySql('SELECT payload FROM sources WHERE hash = ?', [hash]);
    try { return rs.goToFirstRow() ? this.normalizeSource(JSON.parse(rs.getString(0)) as SourceRecord) : undefined; } finally { rs.close(); }
  }
  async putSource(s: SourceRecord): Promise<void> {
    await this.store().executeSql('INSERT OR REPLACE INTO sources (id,hash,payload) VALUES (?,?,?)', [s.id, s.hash, JSON.stringify(s)]);
  }
  async removeSource(id: string): Promise<void> {
    const refs = (await this.tasks(true)).filter((t: TaskRecord) => t.sourceIds.includes(id));
    if (refs.length) { throw new Error('此来源仍被事项或历史引用，不能单独删除。可在设置中清空全部本地记录。'); }
    if ((await this.sourceHistoryTaskIds(id)).length) { throw new Error('此来源仍被历史引用，可归档保留，不能永久删除原图。'); }
    await this.store().executeSql('DELETE FROM sources WHERE id = ?', [id]);
  }
  private normalizeSource(s: SourceRecord): SourceRecord {
    s.tags = s.tags || []; s.note = s.note || ''; s.archived = s.archived === true; return s;
  }
  private async indexHistory(h: HistoryRecord): Promise<void> {
    const ids: Set<string> = new Set<string>();
    if (h.sourceId) { ids.add(h.sourceId); }
    if (h.sourceSnapshot && h.sourceSnapshot.id) { ids.add(h.sourceSnapshot.id); }
    if (h.before) { h.before.sourceIds.forEach((id: string) => ids.add(id)); }
    if (h.after) { h.after.sourceIds.forEach((id: string) => ids.add(id)); }
    for (const id of ids) { await this.store().executeSql('INSERT OR IGNORE INTO source_history (source_id,history_id,task_id) VALUES (?,?,?)', [id,h.id,h.taskId]); }
  }
  async sourceHistoryTaskIds(id: string): Promise<string[]> {
    const rs = await this.store().querySql('SELECT DISTINCT task_id FROM source_history WHERE source_id = ?', [id]); const ids: string[] = [];
    try { while (rs.goToNextRow()) { ids.push(rs.getString(0)); } } finally { rs.close(); } return ids;
  }
  async saveSourceMeta(id: string, name: string, tags: string[], note: string): Promise<SourceRecord> {
    const source = (await this.sources()).find((s: SourceRecord) => s.id === id);
    if (!source) { throw new Error('来源已不存在'); }
    if (!name.trim()) { throw new Error('请填写来源名称'); }
    source.name = name.trim().slice(0,80); source.tags = tags.slice(0,6); source.note = note.trim().slice(0,300);
    await this.putSource(source); return source;
  }
  async archiveSource(id: string, archived: boolean): Promise<SourceRecord> {
    const source = (await this.sources()).find((s: SourceRecord) => s.id === id);
    if (!source) { throw new Error('来源已不存在'); } source.archived = archived; await this.putSource(source); return source;
  }
  async attachSource(task: TaskRecord, sourceId: string): Promise<TaskRecord> {
    const source = (await this.sources()).find((s: SourceRecord) => s.id === sourceId);
    if (!source) { throw new Error('来源已不存在'); }
    if (task.sourceIds.includes(sourceId)) { throw new Error('这份来源已关联，无需重复添加'); }
    return this.saveTask(task, '补充来源 · 保留事项字段', source);
  }
  async detachSource(task: TaskRecord, sourceId: string): Promise<TaskRecord> {
    if (!task.sourceIds.includes(sourceId)) { throw new Error('当前事项未关联此来源'); }
    const next = cloneTask(task); next.sourceIds = next.sourceIds.filter((id: string) => id !== sourceId);
    return this.saveTask(next, '解除来源关联 · 保留原图及历史');
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
      await this.indexHistory(h);
      db.commit(); return next;
    } catch (e) { db.rollBack(); throw new Error((e as Error).message || String(e)); }
  }
  async clear(): Promise<void> {
    const db = this.store(); db.beginTransaction();
    try { await db.executeSql('DELETE FROM source_history'); await db.executeSql('DELETE FROM history'); await db.executeSql('DELETE FROM tasks'); await db.executeSql('DELETE FROM sources'); db.commit(); }
    catch (e) { db.rollBack(); throw new Error((e as Error).message || String(e)); }
  }
}

