import { connection } from '@kit.NetworkKit';

/**
 * Keeps private-LAN car traffic on Wi-Fi/Ethernet instead of allowing the
 * system's network handover service to redirect it to cellular data.
 */
export class LocalNetworkRoute {
  private boundNetId: number = 0;
  private boundHandle?: connection.NetHandle;

  async bind(): Promise<boolean> {
    try {
      const networks: connection.NetHandle[] = await connection.getAllNets();
      const wifi = await this.findByBearer(networks, connection.NetBearType.BEARER_WIFI);
      const selected = wifi !== undefined ? wifi :
        await this.findByBearer(networks, connection.NetBearType.BEARER_ETHERNET);
      if (selected === undefined) {
        return false;
      }
      await connection.setAppNet(selected);
      this.boundNetId = selected.netId;
      this.boundHandle = selected;
      return true;
    } catch (error) {
      return false;
    }
  }

  async release(): Promise<void> {
    if (this.boundNetId === 0 || this.boundHandle === undefined) {
      return;
    }
    try {
      this.boundHandle.netId = 0;
      await connection.setAppNet(this.boundHandle);
      this.boundNetId = 0;
      this.boundHandle = undefined;
    } catch (error) {
      // The OS also releases an app route when the process exits.
    }
  }

  private async findByBearer(networks: connection.NetHandle[],
    bearer: connection.NetBearType): Promise<connection.NetHandle | undefined> {
    for (let index = 0; index < networks.length; index += 1) {
      try {
        const capabilities = await connection.getNetCapabilities(networks[index]);
        if (capabilities.bearerTypes.includes(bearer)) {
          return networks[index];
        }
      } catch (error) {
        // A disappearing network must not prevent checking the remaining ones.
      }
    }
    return undefined;
  }
}
