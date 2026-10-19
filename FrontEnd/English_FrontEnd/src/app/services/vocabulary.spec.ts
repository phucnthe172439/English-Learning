import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { VocabularyService } from './vocabulary';

describe('VocabularyService', () => {
  let service: VocabularyService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient()],
    });
    service = TestBed.inject(VocabularyService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
