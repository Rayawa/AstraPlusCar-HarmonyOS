import { describe, it, expect } from '@ohos/hypium';
import { CarDefaults, CarLimits } from '../main/ets/constants/AppConstants';
import { CarAction } from '../main/ets/models/CarModels';
import { CarApi } from '../main/ets/services/CarApi';

export default function localUnitTest() {
  describe('carConfiguration', () => {
    it('normalizesEndpoint', 0, () => {
      expect(CarApi.normalizeEndpoint('192.168.8.204:8080/')).assertEqual(CarDefaults.ENDPOINT);
      expect(CarApi.normalizeEndpoint('https://car.local///')).assertEqual('https://car.local');
      expect(CarApi.normalizeEndpoint('http://192.168.8.204:8080/api/health'))
        .assertEqual('http://192.168.8.204:8080');
      expect(CarApi.normalizeEndpoint('http://192.168.8.204:8080/api/health/'))
        .assertEqual('http://192.168.8.204:8080');
      expect(CarApi.normalizeEndpoint('http://')).assertEqual('');
      expect(CarApi.normalizeEndpoint('bad host')).assertEqual('');
      expect(CarApi.normalizeEndpoint('http://car.local/path')).assertEqual('');
      expect(CarApi.normalizeEndpoint('http://car.local?mode=test')).assertEqual('');
      expect(CarApi.normalizeEndpoint('http://car.local#panel')).assertEqual('');
    });
    it('keepsProtocolValuesConsistent', 0, () => {
      expect(CarLimits.SPEED_MIN < CarDefaults.SPEED).assertTrue();
      expect(CarDefaults.SPEED < CarLimits.SPEED_MAX).assertTrue();
      expect(CarAction.FORWARD).assertEqual('forward');
      expect(CarAction.SPIN_RIGHT).assertEqual('spin_right');
    });
  });
}
