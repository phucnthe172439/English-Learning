import { afterRenderEffect, Component, ElementRef, inject, viewChild } from '@angular/core';
import { ConfirmService } from '../../services/confirm';

/** A native <dialog> driven by ConfirmService. Esc or "Cancel" answers false. */
@Component({
  selector: 'app-confirm-dialog',
  templateUrl: './confirm-dialog.html',
  styleUrl: './confirm-dialog.css',
})
export class ConfirmDialog {
  protected readonly confirm = inject(ConfirmService);
  private readonly dialog = viewChild.required<ElementRef<HTMLDialogElement>>('dialog');

  constructor() {
    // Open / close the browser dialog whenever a confirmation is requested or answered.
    afterRenderEffect(() => {
      const dialog = this.dialog().nativeElement;
      const isPending = this.confirm.pending() !== null;
      if (isPending && !dialog.open) {
        dialog.showModal();
      } else if (!isPending && dialog.open) {
        dialog.close();
      }
    });
  }

  protected onCancel(event: Event): void {
    event.preventDefault();
    this.confirm.close(false);
  }
}
