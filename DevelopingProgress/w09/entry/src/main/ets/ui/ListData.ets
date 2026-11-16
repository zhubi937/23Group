import { TaskRecord, SourceRecord } from '../domain/Models';

export class TaskListData implements IDataSource {
  private items: TaskRecord[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): TaskRecord { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) { this.listeners.push(listener); } }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((v: DataChangeListener) => v !== listener); }
  replace(items: TaskRecord[]): void { this.items = items; this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded()); }
}
export class SourceListData implements IDataSource {
  private items: SourceRecord[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): SourceRecord { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) { this.listeners.push(listener); } }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((v: DataChangeListener) => v !== listener); }
  replace(items: SourceRecord[]): void { this.items = items; this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded()); }
}
