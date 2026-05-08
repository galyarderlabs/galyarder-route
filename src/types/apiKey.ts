/**
 * API key — authentication credential for accessing the GalyarderRoute proxy.
 */
export interface ApiKey {
  id: string;
  key: string;
  label: string;
  isActive: boolean;
  createdAt: string;
  lastUsedAt?: string;
  usageCount: number;
}
