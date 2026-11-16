import { LedgerIncomeSource } from '../model/Ledger';

const RING_SIZE: number = 104;
const INCOME_COLORS: Resource[] = [
  $r('app.color.ledger_income_gold'), $r('app.color.ledger_income_blue'),
  $r('app.color.ledger_income_green'), $r('app.color.ledger_income_violet'),
  $r('app.color.ledger_income_red'), $r('app.color.ledger_income_teal'),
  $r('app.color.ledger_income_pink'), $r('app.color.ledger_income_gray')
];

export function incomeColor(index: number): Resource {
  return INCOME_COLORS[index % INCOME_COLORS.length];
}

/** 扇区按来源数量占比绘制，文字图例使用接口单独提供的百分比。 */
@Component
export struct LedgerIncomeRing {
  @Prop @Watch('draw') sources: LedgerIncomeSource[] = [];
  @StorageProp('isDarkMode') @Watch('draw') isDarkMode: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  draw(): void {
    if (!this.ready) { return; }
    const host = this.getUIContext().getHostContext();
    if (host === undefined) { return; }
    this.context.clearRect(0, 0, RING_SIZE, RING_SIZE);
    let total: number = 0;
    for (const source of this.sources) { total += source.num; }
    if (total <= 0) { return; }

    const center: number = RING_SIZE / 2;
    const ringWidth: number = 17;
    const radius: number = 50 - ringWidth / 2;
    let angle: number = -Math.PI / 2;
    this.context.lineWidth = ringWidth;
    for (let index: number = 0; index < this.sources.length; index++) {
      const end: number = angle + 2 * Math.PI * this.sources[index].num / total;
      this.context.beginPath();
      this.context.strokeStyle = host.resourceManager.getColorSync(incomeColor(index).id);
      this.context.arc(center, center, radius, angle, end);
      this.context.stroke();
      angle = end;
    }
  }

  build() {
    Canvas(this.context)
      .width(RING_SIZE).height(RING_SIZE).accessibilityLevel('no')
      .onReady((): void => {
        this.ready = true;
        this.draw();
      })
  }
}
