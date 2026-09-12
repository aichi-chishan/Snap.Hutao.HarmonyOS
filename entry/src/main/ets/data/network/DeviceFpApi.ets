/**
 * DeviceFpApi.ets
 * 米哈游设备指纹：POST https://public-data-api.mihoyo.com/device-fp/api/getFp
 * 返回真实 device_fp，注入 x-rpc-device_fp 头可显著降低便笺/战绩接口风控。
 * 参考 Snap Hutao UserFingerprintService（国服）。设备属性模拟为小米系 Android 环境。
 */
import { ApiClient } from './ApiClient';
import { ApiResponse } from '../../model/ApiResponse';
import { Logger } from '../../common/Logger';
import { AppConstants } from '../../common/Constants';

const TAG: string = 'DeviceFpApi';

/** getFp 请求体 */
export class DeviceFpRequest {
  device_id: string = '';
  bbs_device_id: string = '';
  seed_id: string = '';
  seed_time: string = '';
  platform: string = '2';
  device_fp: string = '';
  app_name: string = 'bbs_cn';
  ext_fields: string = '';
}

export class DeviceFpApi {
  static readonly URL: string = 'https://public-data-api.mihoyo.com/device-fp/api/getFp';

  /** 生成 16 位小写 hex（device_id） */
  static randomLowerHex(len: number): string {
    const chars: string = '0123456789abcdef';
    let result: string = '';
    for (let i = 0; i < len; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /** 生成 12 位大写字母+数字（deviceName 等） */
  static randomUpperNumber(len: number): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let result: string = '';
    for (let i = 0; i < len; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /** 生成 UUID 风格 seed_id */
  static randomUuid(): string {
    const hex: string = '0123456789abcdef';
    let s: string = '';
    for (let i = 0; i < 36; i++) {
      const c: string = i === 8 || i === 13 || i === 18 || i === 23 ? '-'
        : (i === 14 ? '4' : hex.charAt(Math.floor(Math.random() * 16)));
      s += c;
    }
    return s;
  }

  /** 构建模拟设备属性 ext_fields（与参考项目一致的小米设备画像） */
  static buildExtFields(): string {
    const device: string = DeviceFpApi.randomUpperNumber(12);
    const product: string = DeviceFpApi.randomUpperNumber(6);
    const fields: Record<string, Object> = {
      'proxyStatus': 0,
      'isRoot': 0,
      'romCapacity': '512',
      'deviceName': device,
      'productName': product,
      'romRemain': '512',
      'hostname': 'dg02-pool03-kvm87',
      'screenSize': '1440x2905',
      'isTablet': 0,
      'aaid': '',
      'model': device,
      'brand': 'XiaoMi',
      'hardware': 'qcom',
      'deviceType': 'OP5913L1',
      'devId': 'REL',
      'serialNumber': 'unknown',
      'sdCapacity': 512215,
      'buildTime': '1693626947000',
      'buildUser': 'android-build',
      'simState': 5,
      'ramRemain': '239814',
      'appUpdateTimeDiff': 1702604034482,
      'deviceInfo': `XiaoMi/${product}/OP5913L1:13/SKQ1.221119.001/T.118e6c7-5aa23-73911:user/release-keys`,
      'vaid': '',
      'buildType': 'user',
      'sdkVersion': '34',
      'ui_mode': 'UI_MODE_TYPE_NORMAL',
      'isMockLocation': 0,
      'cpuType': 'arm64-v8a',
      'isAirMode': 0,
      'ringMode': 2,
      'chargeStatus': 1,
      'manufacturer': 'XiaoMi',
      'emulatorStatus': 0,
      'appMemory': '512',
      'osVersion': '14',
      'vendor': 'unknown',
      'accelerometer': '1.4883357x7.1712894x6.2847486',
      'sdRemain': 239600,
      'buildTags': 'release-keys',
      'packageName': 'com.mihoyo.hyperion',
      'networkType': 'WiFi',
      'oaid': '',
      'debugStatus': 1,
      'ramCapacity': '469679',
      'magnetometer': '20.081251x-27.487501x2.1937501',
      'display': `${product}_13.1.0.181(CN01)`,
      'appInstallTimeDiff': 1688455751496,
      'packageVersion': '2.20.1',
      'gyroscope': '0.030226856x0.014647375x0.010652636',
      'batteryStatus': 100,
      'hasKeyboard': 0,
      'board': 'taro',
    };
    return JSON.stringify(fields);
  }

  /** 构造请求体 */
  static buildRequest(bbsDeviceId: string, existingFp: string): DeviceFpRequest {
    const req: DeviceFpRequest = new DeviceFpRequest();
    req.device_id = DeviceFpApi.randomLowerHex(16);
    req.bbs_device_id = bbsDeviceId;
    req.seed_id = DeviceFpApi.randomUuid();
    req.seed_time = `${Date.now()}`;
    req.platform = '2';
    req.device_fp = existingFp.length > 0 ? existingFp : DeviceFpApi.randomLowerHex(13);
    req.app_name = 'bbs_cn';
    req.ext_fields = DeviceFpApi.buildExtFields();
    return req;
  }

  /** 请求设备指纹，成功返回 device_fp，失败返回空串 */
  static async fetchFingerprint(bbsDeviceId: string, existingFp: string): Promise<string> {
    const req: DeviceFpRequest = DeviceFpApi.buildRequest(bbsDeviceId, existingFp);
    const bodyJson: string = JSON.stringify(req);
    try {
      const resp: ApiResponse = await ApiClient.getInstance().postJson(
        DeviceFpApi.URL, bodyJson, { 'User-Agent': `Snap Hutao/${AppConstants.APP_VERSION}` });
      if (!resp.success || resp.data === undefined) {
        Logger.warn(TAG, `getFp fail retcode=${resp.retcode} msg=${resp.message}`);
        return '';
      }
      const data = resp.data as Record<string, Object>;
      const fp: string = String(data['device_fp'] ?? '');
      if (fp.length > 0) {
        Logger.info(TAG, `getFp ok fp=${fp.substring(0, 8)}...`);
        return fp;
      }
      Logger.warn(TAG, 'getFp returned empty device_fp');
      return '';
    } catch (e) {
      Logger.warn(TAG, `getFp error ${(e as Error).message}`);
      return '';
    }
  }
}
