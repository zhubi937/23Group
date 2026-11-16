export class ThemePalette {
  id: string; name: string; accent: string; soft: string; glow: string; background: string;
  constructor(id: string, name: string, accent: string, soft: string, glow: string, background: string) {
    this.id = id; this.name = name; this.accent = accent; this.soft = soft; this.glow = glow; this.background = background;
  }
}
export const THEMES: ThemePalette[] = [
  new ThemePalette('rose-gold','玫瑰金','#925957','#F2DFDC','#E7BAB1','#FAF5F3'),
  new ThemePalette('morandi-blue','莫兰迪蓝','#49667D','#DDE8F0','#ADC8DD','#F4F7FB'),
  new ThemePalette('matcha','抹茶绿','#577151','#DFE8D8','#BCD2AF','#F5F8F1'),
  new ThemePalette('mist-purple','雾紫','#77618D','#E8DFF1','#CDBBDF','#F8F5FB'),
  new ThemePalette('moon-silver','月光银','#566477','#E3E8EE','#C2CEDD','#F5F7FA'),
  new ThemePalette('apricot','杏桃','#95613D','#F2E2D4','#E7C8A7','#FBF6F0')
];
export function themeById(id: string): ThemePalette { return THEMES.find((t: ThemePalette) => t.id === id) || THEMES[1]; }
export class Appearance {
  themeId: string = 'morandi-blue';
  clearGlass: boolean = false;
  reduceMotion: boolean = false;
}
