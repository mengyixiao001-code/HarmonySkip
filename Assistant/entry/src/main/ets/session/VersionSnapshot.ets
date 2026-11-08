export class VersionRecord { bundle: string = ''; name: string = ''; }
export class VersionSnapshot { run: string = ''; apps: VersionRecord[] = []; }
