import { uiMaterial } from '@kit.ArkUI';
import { Motion } from './Motion';

/** 保留能力检查，同时支持在已挂载节点上清除材质。 */
export class GuardedMaterialModifier implements AttributeModifier<CommonAttribute> {
  private material: uiMaterial.Material | undefined;

  constructor(material: uiMaterial.Material | undefined) {
    this.material = material;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (Motion.detectImmersive()) {
      instance.systemMaterial(this.material ?? uiMaterial.Material.empty);
    }
  }
}
