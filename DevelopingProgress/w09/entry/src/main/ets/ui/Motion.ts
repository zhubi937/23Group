export function clampPage(value: number): number { return Math.max(0,Math.min(2,Number.isFinite(value)?value:0)); }
// A short flick advances one page. A longer drag respects the lens under the finger.
export function dockDestination(progress: number, start: number, velocity: number): number {
  return Math.round(clampPage(Math.abs(velocity)>500 && Math.abs(progress-start)<0.5 ? start+(velocity>0?1:-1) : progress));
}
