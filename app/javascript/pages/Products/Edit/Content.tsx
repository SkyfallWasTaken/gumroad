import { usePage } from "@inertiajs/react";
import * as React from "react";

import { ProductEditProvider, FullEditProps } from "$app/components/ProductEdit/ProductEditProvider";
import { ContentTab } from "$app/components/ProductEdit/ContentTab";

function ContentPage() {
  const props = usePage<FullEditProps>().props;

  return (
    <ProductEditProvider props={props}>
      <ContentTab />
    </ProductEditProvider>
  );
}

export default ContentPage;
