import { HttpClient } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { API_BASE_URL } from './api.config';

export interface Topic {
  topicId: number;
  name: string;
  vocabularyCount: number;
}

export interface WordType {
  wordTypeId: number;
  name: string;
  vocabularyCount: number;
}

/** Topics and word types: used for dropdowns, filters and dashboard stats. */
@Injectable({
  providedIn: 'root'
})
export class LookupService {
  private readonly http = inject(HttpClient);

  getTopics(): Observable<Topic[]> {
    return this.http.get<Topic[]>(`${API_BASE_URL}/Topic`);
  }

  getWordTypes(): Observable<WordType[]> {
    return this.http.get<WordType[]>(`${API_BASE_URL}/WordType`);
  }
}
