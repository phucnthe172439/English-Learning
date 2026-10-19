import { Routes } from '@angular/router';
import { Dashboard } from './pages/dashboard/dashboard';
import { VocabularyForm } from './pages/vocabulary-form/vocabulary-form';

export const routes: Routes = [
  { path: '', component: Dashboard, title: 'Dashboard · English Vocabulary' },
  { path: 'vocabularies/new', component: VocabularyForm, title: 'Add word · English Vocabulary' },
  { path: 'vocabularies/:id/edit', component: VocabularyForm, title: 'Edit word · English Vocabulary' },
  { path: '**', redirectTo: '' },
];
