/**
 * zod schemas for the three remote JSON sources declared in
 * config/sources.public.yml (projects, portfolio, cv). Each SourceEntry's
 * `schema` field names one of these; subzerodev-data-json's own `useJson`
 * has no `validate` parameter (see 20-contract.md §9), so DataProvider and
 * the data hooks apply the matching validator to the result themselves
 * rather than through JsonRequest.validate — the "consumer's schema
 * registry" the contract's SourceEntryCommon.schema comment refers to.
 */
import { z } from 'zod';
import { zodValidator } from 'subzerodev-data-json/zod';
import type { Validator } from 'subzerodev-data-json';

const projectSchema = z
  .object({
    id: z.string().optional(),
    title: z.string(),
    // Real data has explicit `null` (not just omission) on some entries,
    // for both of these fields.
    link: z.string().nullable().optional(),
    lastModified: z.string().nullable().optional(),
    summary: z.string(),
    tags: z.array(z.string()).optional(),
    repoUrl: z.string().optional(),
    draft: z.boolean().optional()
  })
  .passthrough();

const projectSubCategorySchema = z.object({
  name: z.string(),
  projects: z.array(projectSchema)
});

const projectCategorySchema = z.object({
  category: z.string(),
  subCategories: z.array(projectSubCategorySchema)
});

export const projectsSchema = zodValidator(z.array(projectCategorySchema));

// Real data nests technology subCategories arbitrarily deep, mixing plain
// strings (leaf names) with { name, subCategories } objects, and `link` is
// often absent — the schema mirrors that rather than the stricter shape
// FlattenedTechnologyItem's TS type implies.
type TechnologyItemInput = {
  name: string;
  link?: string;
  subCategories?: (string | TechnologyItemInput)[];
};

const technologyItemSchema: z.ZodType<TechnologyItemInput> = z.lazy(() =>
  z.object({
    name: z.string(),
    link: z.string().optional(),
    subCategories: z.array(z.union([z.string(), technologyItemSchema])).optional()
  })
);

const technologySchema = z.object({
  name: z.string(),
  link: z.string().optional(),
  subCategories: z.array(z.union([z.string(), technologyItemSchema])).optional()
});

const statItemSchema = z.object({
  // Real data has occasional numeric `number` values (e.g. a raw count)
  // alongside the usual "20+"-style strings.
  number: z.union([z.string(), z.number()]),
  label: z.string()
});

const portfolioProjectCategorySchema = z
  .object({
    category: z.string(),
    icon: z.string(),
    description: z.string()
  })
  .passthrough();

const portfolioDataSchema = z.object({
  header: z.object({ title: z.string(), subtitle: z.string() }),
  technologies: z.array(technologySchema),
  projects: z.array(portfolioProjectCategorySchema),
  stats: z.array(statItemSchema),
  seo: z.object({ title: z.string(), description: z.string() })
});

export const portfolioSchema = zodValidator(portfolioDataSchema);

const cvLinkSchema = z.object({ label: z.string(), href: z.string() });
const cvBadgeSchema = z.object({ alt: z.string(), src: z.string() });

// Real data has the occasional achievement as a single-key { headline: detail }
// object rather than a plain string (see config/portfolioData.yml-derived
// cvData.yml) — CVTimeline renders both shapes, so the schema accepts both.
const cvAchievementSchema = z.union([z.string(), z.record(z.string(), z.string())]);

const cvRoleSchema = z.object({
  icon: z.string().optional(),
  company: z.string(),
  title: z.string(),
  location: z.string().optional(),
  period: z.string(),
  website: z.string().optional(),
  summary: z.string().optional(),
  achievements: z.array(cvAchievementSchema).optional(),
  tech: z.string().optional()
});

const cvEducationSchema = z.object({
  school: z.string(),
  degree: z.string(),
  details: z.string().optional()
});

const cvProjectSchema = z.object({
  title: z.string(),
  link: z.string().optional(),
  description: z.string(),
  tech: z.string(),
  year: z.union([z.number(), z.string()])
});

const cvOpenSourceSchema = z.object({
  title: z.string(),
  link: z.string().optional(),
  description: z.string(),
  impact: z.string(),
  tech: z.string()
});

const cvTimelineProjectSchema = z.object({
  period: z.string(),
  focus: z.string(),
  projects: z.array(z.string())
});

const cvDataSchema = z.object({
  header: z.object({
    title: z.string(),
    email: z.string().optional(),
    phone: z.string().optional(),
    links: z.array(cvLinkSchema).optional()
  }),
  about: z.object({ title: z.string(), body: z.string() }),
  badges: z.array(cvBadgeSchema).optional(),
  chips: z.array(z.string()).optional(),
  timelineTitle: z.string(),
  roles: z.array(cvRoleSchema),
  educationTitle: z.string().optional(),
  education: z.array(cvEducationSchema).optional(),
  projectsTitle: z.string().optional(),
  projects: z.array(cvProjectSchema).optional(),
  openSourceTitle: z.string().optional(),
  openSource: z.array(cvOpenSourceSchema).optional(),
  timelineProjectsTitle: z.string().optional(),
  timelineProjects: z.array(cvTimelineProjectSchema).optional(),
  quote: z.string().optional()
});

export const cvSchema = zodValidator(cvDataSchema);

export type SchemaId = 'projects' | 'portfolio' | 'cv';

// Typed as Record<SchemaId, Validator<unknown>> (rather than inferred from
// the object literal) so `schemaRegistry[sourceId]` resolves to one concrete
// function type at call sites — indexing with a union key otherwise types
// the value as a union of three distinct function types, and TS doesn't
// narrow the result's `ok` discriminant reliably through that.
export const schemaRegistry: Record<SchemaId, Validator<unknown>> = {
  projects: projectsSchema,
  portfolio: portfolioSchema,
  cv: cvSchema
};
