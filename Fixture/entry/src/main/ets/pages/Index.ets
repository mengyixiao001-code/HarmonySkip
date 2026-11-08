@Entry
@Component
struct Index {
  @State mode: string = 'normal';
  @State challenge: string = '';
  @State receipt: string = '';
  @State waitCount: number = 0;
  private timer: number = -1;

  private clearTimer(): void {
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
  }

  private start(kind: string): void {
    this.clearTimer();
    this.challenge = Date.now().toString();
    this.receipt = '';
    this.mode = kind;
    this.waitCount = kind === 'splash' ? 2 : 0;
    if (this.waitCount > 0) {
      this.timer = setInterval(() => {
        this.waitCount--;
        if (this.waitCount <= 0) { this.clearTimer(); }
      }, 1000);
    }
  }

  aboutToDisappear(): void { this.clearTimer(); }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('轻跳测试页').fontSize(26).fontWeight(FontWeight.Bold)
        if (this.mode === 'normal') {
          Text('这是普通引导页。下方的“跳过”应当一直保留。进入测试后请勿手点广告按钮。').fontSize(17)
          Button('跳过').id('hs_normal_skip').onClick(() => { this.receipt = '普通引导的按钮被点了'; })
          Button('展示模拟开屏广告').onClick(() => { this.start('splash'); })
          Button('展示模拟广告弹窗').onClick(() => { this.start('popup'); })
          Button('展示无 ID 学习样本').onClick(() => { this.start('sample'); })
          Button('展示两层弹窗').onClick(() => { this.start('layer1'); })
        } else if (this.mode === 'sample') {
          Text('广告')
          Button('跳过').onClick(() => { this.finish(); })
        } else if (this.mode === 'layer1' || this.mode === 'layer2') {
          Text(this.mode === 'layer1' ? '活动广告' : '优惠广告')
          if (this.mode === 'layer1') {
            Button('关闭').id('hs_layer_one').onClick(() => { this.mode = 'layer2'; })
          } else {
            Button('关闭').id('hs_layer_two').onClick(() => { this.finish(); })
          }
        } else if (this.mode === 'splash' || this.mode === 'popup') {
          Column({ space: 14 }) {
            Text('测试广告').id('hs_ad_marker')
            Text(this.challenge).id('hs_challenge')
            if (this.mode === 'splash') {
              Button(this.waitCount > 0 ? '请稍候 ' + this.waitCount : '跳过广告')
                .id('hs_splash_skip').accessibilityDescription('hs_splash_action').enabled(this.waitCount === 0)
                .onClick(() => { this.finish(); })
            } else {
              Button('关闭广告').id('hs_popup_close').accessibilityDescription('hs_popup_action').onClick(() => { this.finish(); })
            }
          }.width('100%').padding(24).backgroundColor('#E1EDE9').borderRadius(16)
        } else {
          Text('广告已关闭').fontSize(24).fontWeight(FontWeight.Bold)
          Text(this.challenge).id('hs_receipt')
        }
        if (this.mode !== 'normal') {
          Button('回到普通引导').onClick(() => { this.clearTimer(); this.mode = 'normal'; this.receipt = ''; })
        }
        Text(this.receipt).fontColor('#344840')
      }.width('100%').padding(24)
    }.width('100%').height('100%')
  }

  private finish(): void {
    this.mode = 'done';
    this.receipt = '本次回执 ' + this.challenge;
  }
}
