import { uiMaterial } from '@kit.ArkUI';
import { Motion } from './Motion';

/** Keep the API26 method invocation itself outside the API24 rendering path. */
export class GuardedMaterialModifier implements AttributeModifier<CommonAttribute> {
  private material: uiMaterial.Material | undefined;

  constructor(material: uiMaterial.Material | undefined) {
    this.material = material;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (Motion.detectImmersive() && this.material !== undefined) {
      instance.systemMaterial(this.material);
    }
  }
}
