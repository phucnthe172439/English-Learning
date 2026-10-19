import { Component, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed, toObservable } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';
import { catchError, debounceTime, forkJoin, of, switchMap, tap } from 'rxjs';
import { apiErrorMessage } from '../../services/api-error';
import { ConfirmService } from '../../services/confirm';
import { LookupService, Topic, WordType } from '../../services/lookup';
import { ToastService } from '../../services/toast';
import { Vocabulary, VocabularyService } from '../../services/vocabulary';

@Component({
  selector: 'app-dashboard',
  imports: [RouterLink],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css',
})
export class Dashboard {
  private readonly vocabularyService = inject(VocabularyService);
  private readonly lookupService = inject(LookupService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);

  // ----- data from the API -----
  protected readonly words = signal<Vocabulary[]>([]);
  protected readonly topics = signal<Topic[]>([]);
  protected readonly wordTypes = signal<WordType[]>([]);
  protected readonly loading = signal(true);
  protected readonly loadError = signal<string | null>(null);
  protected readonly deletingId = signal<number | null>(null);

  // ----- filters (sent to the API as ?search=&topicId=&wordTypeId=) -----
  protected readonly search = signal('');
  protected readonly topicId = signal<number | null>(null);
  protected readonly wordTypeId = signal<number | null>(null);
  private readonly reloadCount = signal(0);

  protected readonly hasFilters = computed(
    () => this.search().trim() !== '' || this.topicId() !== null || this.wordTypeId() !== null,
  );

  // ----- stats -----
  protected readonly totalWords = computed(() =>
    this.topics().reduce((sum, topic) => sum + topic.vocabularyCount, 0),
  );
  protected readonly topicsInUse = computed(
    () => this.topics().filter((topic) => topic.vocabularyCount > 0).length,
  );
  protected readonly topicsByCount = computed(() =>
    [...this.topics()].sort((a, b) => b.vocabularyCount - a.vocabularyCount || a.name.localeCompare(b.name)),
  );
  private readonly maxTopicCount = computed(() =>
    Math.max(0, ...this.topics().map((topic) => topic.vocabularyCount)),
  );

  constructor() {
    this.loadLookups();

    // Every time a filter changes (or reload() is called), ask the API again.
    // debounceTime waits until the user stops typing; switchMap cancels the previous request.
    const query = computed(() => ({
      search: this.search(),
      topicId: this.topicId(),
      wordTypeId: this.wordTypeId(),
      reload: this.reloadCount(),
    }));

    toObservable(query)
      .pipe(
        debounceTime(250),
        tap(() => this.loading.set(true)),
        switchMap((filter) =>
          this.vocabularyService.getAll(filter).pipe(
            tap(() => this.loadError.set(null)),
            catchError((error) => {
              this.loadError.set(apiErrorMessage(error));
              return of<Vocabulary[]>([]);
            }),
          ),
        ),
        takeUntilDestroyed(),
      )
      .subscribe((words) => {
        this.words.set(words);
        this.loading.set(false);
      });
  }

  protected reload(): void {
    this.loadLookups();
    this.reloadCount.update((count) => count + 1);
  }

  protected onSearch(event: Event): void {
    this.search.set((event.target as HTMLInputElement).value);
  }

  protected onTopicChange(event: Event): void {
    this.topicId.set(Dashboard.idFromSelect(event));
  }

  protected onWordTypeChange(event: Event): void {
    this.wordTypeId.set(Dashboard.idFromSelect(event));
  }

  /** Clicking a bar filters the table by that topic; clicking it again removes the filter. */
  protected toggleTopic(topicId: number): void {
    this.topicId.update((current) => (current === topicId ? null : topicId));
  }

  protected clearFilters(): void {
    this.search.set('');
    this.topicId.set(null);
    this.wordTypeId.set(null);
  }

  protected barWidth(count: number): number {
    const max = this.maxTopicCount();
    return max === 0 ? 0 : (count / max) * 100;
  }

  protected async remove(word: Vocabulary): Promise<void> {
    const confirmed = await this.confirm.ask({
      title: 'Delete this word?',
      message: `"${word.word}" (${word.meaning}) will be permanently deleted.`,
      confirmText: 'Delete',
    });
    if (!confirmed) {
      return;
    }

    this.deletingId.set(word.vocabularyId);
    this.vocabularyService.delete(word.vocabularyId).subscribe({
      next: () => {
        this.words.update((list) => list.filter((w) => w.vocabularyId !== word.vocabularyId));
        this.deletingId.set(null);
        this.loadLookups(); // refresh the counts
        this.toast.success(`Deleted "${word.word}".`);
      },
      error: (error) => {
        this.deletingId.set(null);
        this.toast.error(apiErrorMessage(error));
      },
    });
  }

  private loadLookups(): void {
    forkJoin({
      topics: this.lookupService.getTopics(),
      wordTypes: this.lookupService.getWordTypes(),
    }).subscribe({
      next: ({ topics, wordTypes }) => {
        this.topics.set(topics);
        this.wordTypes.set(wordTypes);
      },
      error: (error) => this.loadError.set(apiErrorMessage(error)),
    });
  }

  private static idFromSelect(event: Event): number | null {
    const value = (event.target as HTMLSelectElement).value;
    return value ? Number(value) : null;
  }
}
