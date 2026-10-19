import { HttpClient, HttpParams } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { API_BASE_URL } from './api.config';

/** A word as returned by the API (GET /api/Vocabulary). */
export interface Vocabulary {
  vocabularyId: number;
  word: string;
  meaning: string;
  wordTypeId: number;
  wordTypeName: string;
  topicId: number;
  topicName: string;
}

/** Body sent to POST /api/Vocabulary and PUT /api/Vocabulary/{id}. */
export interface VocabularyRequest {
  word: string;
  meaning: string;
  wordTypeId: number;
  topicId: number;
}

/** Optional filters, sent as query string: ?topicId=1&wordTypeId=2&search=app */
export interface VocabularyFilter {
  topicId?: number | null;
  wordTypeId?: number | null;
  search?: string;
}

@Injectable({
  providedIn: 'root'
})
export class VocabularyService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${API_BASE_URL}/Vocabulary`;

  getAll(filter: VocabularyFilter = {}): Observable<Vocabulary[]> {
    let params = new HttpParams();
    if (filter.topicId) {
      params = params.set('topicId', filter.topicId);
    }
    if (filter.wordTypeId) {
      params = params.set('wordTypeId', filter.wordTypeId);
    }
    if (filter.search?.trim()) {
      params = params.set('search', filter.search.trim());
    }
    return this.http.get<Vocabulary[]>(this.apiUrl, { params });
  }

  getById(id: number): Observable<Vocabulary> {
    return this.http.get<Vocabulary>(`${this.apiUrl}/${id}`);
  }

  create(request: VocabularyRequest): Observable<Vocabulary> {
    return this.http.post<Vocabulary>(this.apiUrl, request);
  }

  update(id: number, request: VocabularyRequest): Observable<void> {
    return this.http.put<void>(`${this.apiUrl}/${id}`, request);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }
}
