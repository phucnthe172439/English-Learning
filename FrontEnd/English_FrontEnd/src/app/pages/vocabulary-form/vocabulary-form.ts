import { Component, inject, signal } from '@angular/core';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { forkJoin, Observable } from 'rxjs';
import { apiErrorMessage } from '../../services/api-error';
import { LookupService, Topic, WordType } from '../../services/lookup';
import { ToastService } from '../../services/toast';
import { VocabularyService } from '../../services/vocabulary';

/**
 * One page for both routes:
 *   /vocabularies/new        -> create
 *   /vocabularies/:id/edit   -> load the word, then update
 */
@Component({
  selector: 'app-vocabulary-form',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './vocabulary-form.html',
  styleUrl: './vocabulary-form.css',
})
export class VocabularyForm {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly vocabularyService = inject(VocabularyService);
  private readonly lookupService = inject(LookupService);
  private readonly toast = inject(ToastService);

  /** The id from the URL, or null when creating. */
  protected readonly id = VocabularyForm.idFromRoute(this.route.snapshot.paramMap.get('id'));
  protected readonly isEdit = this.id !== null;

  protected readonly topics = signal<Topic[]>([]);
  protected readonly wordTypes = signal<WordType[]>([]);
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);

  // Same rules as the API's VocabularyRequest ([Required], [StringLength], [Range(1, ...)])
  protected readonly form = inject(NonNullableFormBuilder).group({
    word: ['', [Validators.required, Validators.pattern(/\S/), Validators.maxLength(100)]],
    meaning: ['', [Validators.required, Validators.pattern(/\S/), Validators.maxLength(500)]],
    wordTypeId: [0, Validators.min(1)],
    topicId: [0, Validators.min(1)],
  });

  constructor() {
    forkJoin({
      topics: this.lookupService.getTopics(),
      wordTypes: this.lookupService.getWordTypes(),
    }).subscribe({
      next: ({ topics, wordTypes }) => {
        this.topics.set(topics);
        this.wordTypes.set(wordTypes);
        if (!this.isEdit) {
          this.loading.set(false);
        }
      },
      error: (error) => this.leave(apiErrorMessage(error)),
    });

    if (this.id !== null) {
      this.vocabularyService.getById(this.id).subscribe({
        next: (word) => {
          this.form.setValue({
            word: word.word,
            meaning: word.meaning,
            wordTypeId: word.wordTypeId,
            topicId: word.topicId,
          });
          this.loading.set(false);
        },
        error: (error) => this.leave(apiErrorMessage(error)),
      });
    }
  }

  /** Show a field's error only after the user touched it (or tried to submit). */
  protected showError(field: 'word' | 'meaning' | 'wordTypeId' | 'topicId'): boolean {
    const control = this.form.controls[field];
    return control.invalid && control.touched;
  }

  protected save(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    const request = this.form.getRawValue();
    const call: Observable<unknown> =
      this.id === null
        ? this.vocabularyService.create(request)
        : this.vocabularyService.update(this.id, request);

    this.saving.set(true);
    call.subscribe({
      next: () => {
        this.toast.success(this.isEdit ? `Updated "${request.word}".` : `Added "${request.word}".`);
        this.router.navigate(['/']);
      },
      error: (error) => {
        this.saving.set(false);
        this.toast.error(apiErrorMessage(error));
      },
    });
  }

  /** Something went wrong while loading (e.g. 404): tell the user and go back. */
  private leave(message: string): void {
    this.toast.error(message);
    this.router.navigate(['/']);
  }

  private static idFromRoute(value: string | null): number | null {
    const id = Number(value);
    return value !== null && Number.isInteger(id) && id > 0 ? id : null;
  }
}
