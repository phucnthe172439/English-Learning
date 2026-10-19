import { Injectable, signal } from '@angular/core';

export interface ConfirmRequest {
  title: string;
  message: string;
  confirmText?: string;
}

interface PendingConfirm extends ConfirmRequest {
  resolve: (confirmed: boolean) => void;
}

/**
 * Asks the user to confirm an action. Rendered by <app-confirm-dialog>.
 *
 *   if (await this.confirm.ask({ title: 'Delete word?', message: '...' })) { ... }
 */
@Injectable({
  providedIn: 'root'
})
export class ConfirmService {
  readonly pending = signal<PendingConfirm | null>(null);

  ask(request: ConfirmRequest): Promise<boolean> {
    this.pending()?.resolve(false);
    return new Promise((resolve) => this.pending.set({ ...request, resolve }));
  }

  close(confirmed: boolean): void {
    const pending = this.pending();
    if (!pending) {
      return;
    }
    this.pending.set(null);
    pending.resolve(confirmed);
  }
}
