export class ScreenRoute {
  screen: string;
  id: string;
  constructor(screen: string = 'home', id: string = '') { this.screen=screen; this.id=id; }
}
// Keep record identities as well as page names when following source/task links.
export class RouteTrail {
  private routes: ScreenRoute[] = [new ScreenRoute()];
  reset(): void { this.routes=[new ScreenRoute()]; }
  current(): ScreenRoute { const route=this.routes[this.routes.length-1]; return new ScreenRoute(route.screen,route.id); }
  enter(screen: string,id: string = ''): void {
    if (screen==='home') { this.reset(); return; }
    const current=this.current();
    if (current.screen!==screen || current.id!==id) { this.routes.push(new ScreenRoute(screen,id)); }
  }
  back(): ScreenRoute { if (this.routes.length>1) { this.routes.pop(); } return this.current(); }
}
